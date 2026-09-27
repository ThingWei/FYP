"""Train and export the EfficientNet-B0 risk classifier.

Expected input is an ImageFolder tree with ``normal`` and ``risky`` folders.
No accuracy is claimed until a curated, independently reviewed dataset is used.
"""

import argparse
import json
from pathlib import Path

import torch
from torch import nn
from torch.utils.data import DataLoader, random_split
from torchvision import datasets, models, transforms


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dataset', type=Path)
    parser.add_argument('--epochs', type=int, default=8)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    torch.manual_seed(args.seed)
    transform = transforms.Compose([
        transforms.Resize((224, 224)), transforms.RandomHorizontalFlip(),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    dataset = datasets.ImageFolder(args.dataset, transform=transform)
    if set(dataset.classes) != {'normal', 'risky'} or len(dataset) < 40:
        raise ValueError('Dataset needs normal/risky folders and at least 40 reviewed images')
    validation_size = max(8, int(len(dataset) * 0.2))
    train, validation = random_split(
        dataset, [len(dataset) - validation_size, validation_size],
        generator=torch.Generator().manual_seed(args.seed),
    )
    loaders = {
        'train': DataLoader(train, batch_size=16, shuffle=True),
        'validation': DataLoader(validation, batch_size=16),
    }
    model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.DEFAULT)
    for parameter in model.features.parameters():
        parameter.requires_grad = False
    model.classifier[1] = nn.Linear(model.classifier[1].in_features, 2)
    optimizer = torch.optim.AdamW(model.classifier.parameters(), lr=1e-3)
    loss_function = nn.CrossEntropyLoss()
    metrics = []
    for epoch in range(args.epochs):
        epoch_result = {'epoch': epoch + 1}
        for phase in ('train', 'validation'):
            model.train(phase == 'train')
            correct = count = 0
            loss_total = 0.0
            for inputs, labels in loaders[phase]:
                optimizer.zero_grad()
                with torch.set_grad_enabled(phase == 'train'):
                    outputs = model(inputs)
                    loss = loss_function(outputs, labels)
                    if phase == 'train':
                        loss.backward()
                        optimizer.step()
                loss_total += float(loss.item()) * inputs.size(0)
                correct += int((outputs.argmax(1) == labels).sum())
                count += inputs.size(0)
            epoch_result[f'{phase}Loss'] = loss_total / count
            epoch_result[f'{phase}Accuracy'] = correct / count
        metrics.append(epoch_result)
    root = Path(__file__).resolve().parents[2]
    (root / 'models').mkdir(exist_ok=True)
    (root / 'metrics').mkdir(exist_ok=True)
    model.eval()
    scripted = torch.jit.script(model)
    scripted.save(str(root / 'models' / 'image_risk_efficientnet.pt'))
    (root / 'metrics' / 'image_risk_metrics.json').write_text(
        json.dumps({'classes': dataset.classes, 'images': len(dataset), 'epochs': metrics}, indent=2),
        encoding='utf-8',
    )


if __name__ == '__main__':
    main()
