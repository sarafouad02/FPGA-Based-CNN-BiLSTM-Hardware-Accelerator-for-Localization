import torch
import torch.nn as nn

class VisualFeatureCNN(nn.Module):
    def __init__(self):
        super(VisualFeatureCNN, self).__init__()

        # Define shared convolutional layers with max-pooling
        self.conv1 = nn.Sequential(
            nn.Conv2d(in_channels=4, out_channels=4, kernel_size=3, stride=1, padding=1),
            nn.BatchNorm2d(4),
            nn.ReLU(),
            nn.MaxPool2d(kernel_size=2, stride=2)  # 2x2 max-pooling
        )
        self.conv2 = nn.Sequential(
            nn.Conv2d(in_channels=4, out_channels=8, kernel_size=3, stride=1, padding=1),
            nn.BatchNorm2d(8),
            nn.ReLU(),
            nn.MaxPool2d(kernel_size=2, stride=2)
        )
        self.conv3 = nn.Sequential(
            nn.Conv2d(in_channels=8, out_channels=8, kernel_size=3, stride=1, padding=1),
            nn.BatchNorm2d(8),
            nn.ReLU(),
            nn.MaxPool2d(kernel_size=2, stride=2)
        )
        self.conv4 = nn.Sequential(
            nn.Conv2d(in_channels=8, out_channels=16, kernel_size=3, stride=1, padding=1),
            nn.BatchNorm2d(16),
            nn.ReLU(),
            nn.MaxPool2d(kernel_size=2, stride=2)
        )
        self.conv5 = nn.Sequential(
            nn.Conv2d(in_channels=16, out_channels=8, kernel_size=3, stride=1, padding=1),
            nn.BatchNorm2d(8),
            nn.ReLU(),
            nn.MaxPool2d(kernel_size=2, stride=2)
        )
        self.conv6 = nn.Sequential(
            nn.Conv2d(in_channels=8, out_channels=6, kernel_size=3, stride=1, padding=1),
            nn.BatchNorm2d(6),
            nn.ReLU(),
            nn.MaxPool2d(kernel_size=2, stride=2)
        )

        # Calculate the flattened size dynamically using dummy input
        # with torch.no_grad():
        #     dummy_input = torch.zeros(1, 4, 120, 188)  # Dummy batch for each cam
        #     dummy_output = self.conv6(self.conv5(self.conv4(
        #         self.conv3(self.conv2(self.conv1(dummy_input))))))
        #     self.flattened_size = dummy_output.numel()

        # After 6 pools on 64×64, each map is 1×1, channels = 6
        self.flattened_size = 6

        # Fully connected layers for final output
        self.fc1 = nn.Sequential(
            nn.Linear(self.flattened_size, 100),  # Adjust for concatenated features
            nn.ReLU()
        )
        self.fc2 = nn.Sequential(
            nn.Linear(100, 50),
            nn.ReLU(),
            nn.Dropout(p=0.5)  # Dropout added to FC2 only
        )
        self.fc3 = nn.Sequential(
            nn.Linear(50, 3),
        )

    def forward(self, cam0_frames, cam1_frames):

        # Concatenate both cams along the channel dimension
        combined_features = torch.cat((cam0_frames, cam1_frames), dim=1)  # Concatenate along the channel dimension

        # Process combined frames through shared layers
        cam_features = self.conv1(combined_features)
        cam_features = self.conv2(cam_features)
        cam_features = self.conv3(cam_features)
        cam_features = self.conv4(cam_features)
        cam_features = self.conv5(cam_features)
        cam_features = self.conv6(cam_features)

        # Flatten for FC layers
        cam_features = cam_features.view(cam_features.size(0), -1)

        # Fully connected layers
        x = self.fc1(cam_features)
        x = self.fc2(x)
        x = self.fc3(x)

        return x
    
# import torch
# from torchinfo import summary
# from model import VisualFeatureCNN

# # Instantiate
# device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
# model = VisualFeatureCNN().to(device)

# # Make dummy inputs for cam0 and cam1: each (batch, 2, H, W)
# batch_size = 1
# H, W = 64, 64
# cam0 = torch.zeros(batch_size, 2, H, W, device=device)
# cam1 = torch.zeros(batch_size, 2, H, W, device=device)

# # Print summary. Pass input_data as a tuple of tensors.
# summary(
#     model,
#     input_data=(cam0, cam1),
#     col_names=("input_size", "output_size", "num_params", "trainable"),
#     verbose=2
# )
