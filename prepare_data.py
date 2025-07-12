import os
import pandas as pd
import torch
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms
from PIL import Image

class DataSynchronizer:
    def __init__(self, cam0_csv, cam1_csv, cam0_folder, cam1_folder, gt_csv):
        self.cam0_csv = cam0_csv
        self.cam1_csv = cam1_csv
        self.cam0_folder = cam0_folder
        self.cam1_folder = cam1_folder
        self.gt_csv = gt_csv

    def load_timestamps_and_images(self, csv_path, img_folder):
        df = pd.read_csv(csv_path)
        df['filename'] = df['filename'].apply(lambda fn: os.path.join(img_folder, fn))
        return df[['#timestamp [ns]', 'filename']]

    def load_groundtruth(self):
        gt = pd.read_csv(self.gt_csv)
        return gt[['#timestamp', ' p_RS_R_x [m]', ' p_RS_R_y [m]', ' p_RS_R_z [m]']]

    def synchronize(self):
        cam0 = self.load_timestamps_and_images(self.cam0_csv, self.cam0_folder)
        cam1 = self.load_timestamps_and_images(self.cam1_csv, self.cam1_folder)
        merged = pd.merge(cam0, cam1, on='#timestamp [ns]', suffixes=('_cam0', '_cam1'))
        merged = merged.rename(columns={'#timestamp [ns]': '#timestamp'})
        gt = self.load_groundtruth()
        sync = pd.merge(merged, gt, on='#timestamp', how='inner')
        sync = sync.rename(columns={
            'filename_cam0': 'image_cam0',
            'filename_cam1': 'image_cam1',
            ' p_RS_R_x [m]': 'x',
            ' p_RS_R_y [m]': 'y',
            ' p_RS_R_z [m]': 'z',
        })
        return sync

class LocalizationDataset(Dataset):
    def __init__(self, sync_df, image_size=(64,64), transform=None):
        self.df = sync_df.reset_index(drop=True)
        self.transform = transform
        self.image_size = image_size

    def __len__(self):
        return len(self.df) - 1

    def __getitem__(self, i):
        row0 = self.df.iloc[i]
        row1 = self.df.iloc[i+1]
        # load images
        def load_gray(path):
            img = Image.open(path).convert('L').resize(self.image_size)
            t = transforms.ToTensor()(img)  # 1×H×W
            return t
        c0f0 = load_gray(row0.image_cam0)
        c0f1 = load_gray(row1.image_cam0)
        c1f0 = load_gray(row0.image_cam1)
        c1f1 = load_gray(row1.image_cam1)

        # stack: (batch_dim)  concatenate frames on channel dim → 2×1×H×W?
        # your model expects (batch, 2, H, W) per camera
        cam0 = torch.cat([c0f0, c0f1], dim=0)  # shape (2, H, W)
        cam1 = torch.cat([c1f0, c1f1], dim=0)

        pos1 = torch.tensor([row1.x, row1.y, row1.z], dtype=torch.float32)
        return (cam0, cam1), pos1

def get_dataloaders(root_dir, level_name, batch_size=32):
    base = os.path.join(root_dir, level_name, 'mav0')
    cam0_csv = os.path.join(base, 'cam0/data.csv')
    cam1_csv = os.path.join(base, 'cam1/data.csv')
    cam0_folder = os.path.join(base, 'cam0/data')
    cam1_folder = os.path.join(base, 'cam1/data')
    gt_csv = os.path.join(base, 'state_groundtruth_estimate0/data.csv')

    sync = DataSynchronizer(cam0_csv, cam1_csv, cam0_folder, cam1_folder, gt_csv).synchronize()
    dataset = LocalizationDataset(sync)
    n = len(dataset)
    n_train = int(0.8 * n)
    train_ds = torch.utils.data.Subset(dataset, list(range(n_train)))
    test_ds  = torch.utils.data.Subset(dataset, list(range(n_train, n)))

    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True, num_workers=4)
    test_loader  = DataLoader(test_ds,  batch_size=batch_size, shuffle=False, num_workers=4)
    return train_loader, test_loader
