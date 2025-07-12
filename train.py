import os
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import random_split, DataLoader
from prepare_data import DataSynchronizer, LocalizationDataset
from model import VisualFeatureCNN

def init_weights(m):
    if isinstance(m, (nn.Conv2d, nn.Linear)):
        nn.init.kaiming_normal_(m.weight)
        if m.bias is not None:
            nn.init.zeros_(m.bias)
    elif isinstance(m, nn.BatchNorm2d):
        nn.init.ones_(m.weight)
        nn.init.zeros_(m.bias)

def train_one_epoch(model, loader, criterion, optimizer, device):
    model.train()
    running = 0.0
    for (c0, c1), pos in loader:
        c0, c1, pos = c0.to(device), c1.to(device), pos.to(device)
        optimizer.zero_grad()
        out = model(c0, c1)
        loss = criterion(out, pos)
        loss.backward()
        optimizer.step()
        running += loss.item() * c0.size(0)
    return running / len(loader.dataset)

def evaluate(model, loader, criterion, device):
    model.eval()
    running = 0.0
    with torch.no_grad():
        for (c0, c1), pos in loader:
            c0, c1, pos = c0.to(device), c1.to(device), pos.to(device)
            out = model(c0, c1)
            running += criterion(out, pos).item() * c0.size(0)
    return running / len(loader.dataset)

if __name__ == '__main__':
    root        = 'D:/UNI/Graduation project/EuRoC_dataset'
    levels      = ['V1_01_easy']
    train_fracs = [0.8]
    device      = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    patience    = 3
    max_epochs  = 20

    for frac in train_fracs:
        print(f"\n=== TRAINING with train_frac = {frac:.2f} ===")
        for lvl_idx, lvl in enumerate(levels):
            print(f"\n--- LEVEL: {lvl} ---")

            # 1) load & sync
            sync = DataSynchronizer(
                cam0_csv    = os.path.join(root,lvl,'mav0/cam0/data.csv'),
                cam1_csv    = os.path.join(root,lvl,'mav0/cam1/data.csv'),
                cam0_folder = os.path.join(root,lvl,'mav0/cam0/data'),
                cam1_folder = os.path.join(root,lvl,'mav0/cam1/data'),
                gt_csv      = os.path.join(root,lvl,'mav0/state_groundtruth_estimate0/data.csv')
            ).synchronize()
            full_ds = LocalizationDataset(sync, image_size=(64,64))

            # 2) reproducible split train/val
            N       = len(full_ds)
            n_train = int(frac * N)
            n_val   = N - n_train
            # seed derived from level and frac so test.py can repeat it
            seed = 1000*lvl_idx + int(frac*100)
            g = torch.Generator().manual_seed(seed)
            train_ds, val_ds = random_split(full_ds, [n_train, n_val], generator=g)

            train_loader = DataLoader(train_ds, batch_size=32, shuffle=True,  num_workers=4)
            val_loader   = DataLoader(val_ds,   batch_size=32, shuffle=False, num_workers=4)

            # 3) model & training setup
            model     = VisualFeatureCNN().to(device)
            model.apply(init_weights)
            criterion = nn.MSELoss()
            optimizer = optim.SGD(model.parameters(), lr=1e-3, momentum=0.95)
            scheduler = optim.lr_scheduler.StepLR(optimizer, step_size=5, gamma=0.5)

            # 4) train + early stop on val_loss
            best_val = float('inf')
            epochs_no_improve = 0
            best_state = None

            for epoch in range(1, max_epochs+1):
                tr_loss = train_one_epoch(model, train_loader, criterion, optimizer, device)
                val_loss  = evaluate(model, val_loader,   criterion, device=device)
                print(f"Epoch {epoch:>2} | Train: {tr_loss:.4f} | Val: {val_loss:.4f}")

                if val_loss < best_val:
                    best_val = val_loss
                    epochs_no_improve = 0
                    best_state = model.state_dict()
                else:
                    epochs_no_improve += 1
                    if epochs_no_improve >= patience:
                        print(f"→ Early stopping at epoch {epoch}")
                        break

                scheduler.step()

            # 5) save best
            model.load_state_dict(best_state)
            out_dir = "checkpoints"
            os.makedirs(out_dir, exist_ok=True)
            fname = f"{out_dir}/cnn_{lvl}_frac{int(frac*100)}.pth"
            torch.save(best_state, fname)
            print(f"Saved {fname} (best val={best_val:.4f})")
