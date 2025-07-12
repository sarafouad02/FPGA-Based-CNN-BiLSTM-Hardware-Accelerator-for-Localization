import os
import warnings
import torch
import numpy as np
from torch.utils.data import random_split, DataLoader
from prepare_data import DataSynchronizer, LocalizationDataset
from model import VisualFeatureCNN

# suppress that pickle warning
warnings.filterwarnings("ignore",
    message="You are using torch.load with weights_only=False",
    category=FutureWarning)

def test_model(model, loader, device):
    model.eval()
    all_preds, all_gts = [], []
    with torch.no_grad():
        for (c0, c1), pos in loader:
            c0, c1 = c0.to(device), c1.to(device)
            out = model(c0, c1).cpu().numpy()
            all_preds.append(out)
            all_gts.append(pos.numpy())
    preds = np.vstack(all_preds)
    gts   = np.vstack(all_gts)
    rmse_axes    = np.sqrt(((preds-gts)**2).mean(axis=0))
    rmse_overall = np.sqrt(((preds-gts)**2).mean())
    return rmse_axes, rmse_overall, preds.shape[0]

if __name__ == '__main__':
    root        = 'D:/UNI/Graduation project/EuRoC_dataset'
    levels      = ['V1_01_easy']
    train_fracs = [0.8]
    device      = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

    print("\n=== TEST RMSE ON HELD-OUT SET ===")
    print(f"{'Level':12s} {'Frac':>4s} {'#samples':>8s}  {'RMSE_x':>7s} {'RMSE_y':>7s} {'RMSE_z':>7s} {'Overall':>8s}")
    print("-"*60)

    for frac in train_fracs:
        for lvl_idx, lvl in enumerate(levels):
            # 1) load & sync
            sync = DataSynchronizer(
                cam0_csv    = os.path.join(root,lvl,'mav0/cam0/data.csv'),
                cam1_csv    = os.path.join(root,lvl,'mav0/cam1/data.csv'),
                cam0_folder = os.path.join(root,lvl,'mav0/cam0/data'),
                cam1_folder = os.path.join(root,lvl,'mav0/cam1/data'),
                gt_csv      = os.path.join(root,lvl,'mav0/state_groundtruth_estimate0/data.csv')
            ).synchronize()
            full_ds = LocalizationDataset(sync, image_size=(64,64))

            # 2) reproduce split
            N       = len(full_ds)
            n_train = int(frac * N)
            n_val   = N - n_train
            seed = 1000*lvl_idx + int(frac*100)
            g = torch.Generator().manual_seed(seed)
            _, val_ds = random_split(full_ds, [n_train, n_val], generator=g)
            val_loader = DataLoader(val_ds, batch_size=32, shuffle=False, num_workers=4)

            # 3) load checkpoint
            ckpt = f"checkpoints/cnn_{lvl}_frac{int(frac*100)}.pth"
            model = VisualFeatureCNN().to(device)
            state = torch.load(ckpt, map_location=device)
            model.load_state_dict(state)

            # 4) test
            axes, overall, n = test_model(model, val_loader, device)
            print(f"{lvl:12s} {int(frac*100):4d}% {n:8d}  "
                  f"{axes[0]:7.4f} {axes[1]:7.4f} {axes[2]:7.4f} {overall:8.4f}")
