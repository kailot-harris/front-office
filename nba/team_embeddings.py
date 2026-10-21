"""
Team & Entity Embedding Network
File: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/team_embeddings.py
"""

import sys
import os
import pandas as pd
import numpy as np

OUTPUT_EMBEDDINGS = "team_embeddings.csv"
OUTPUT_SIMILARITY = "team_similarity_matrix.csv"
CSV_TRAIN_SOURCE = "cache/games_for_embeddings.csv"

def train_embeddings_svd_fallback(df):
    """Zero-dependency SVD factorizer when PyTorch is not present."""
    print("[Embedding Agent] Executing SVD style-matchup factorization (NumPy engine)...")
    teams = sorted(list(set(df["home_team"].unique()).union(set(df["away_team"].unique()))))
    team_idx = {t: i for i, t in enumerate(teams)}
    n_teams = len(teams)
    
    win_matrix = np.zeros((n_teams, n_teams))
    for _, row in df.iterrows():
        h = team_idx[row["home_team"]]
        a = team_idx[row["away_team"]]
        win_matrix[h, a] += (1.0 if row["home_win"] else -1.0)
        
    u, s, vt = np.linalg.svd(win_matrix)
    dim = 16
    emb = u[:, :dim] * np.sqrt(s[:dim])
    
    emb_df = pd.DataFrame(emb, columns=[f"emb_{i+1}" for i in range(dim)])
    emb_df.insert(0, "team_id", teams)
    emb_df.to_csv(OUTPUT_EMBEDDINGS, index=False)
    
    # Cosine Similarity Matrix
    norm = np.linalg.norm(emb, axis=1, keepdims=True) + 1e-8
    normalized_emb = emb / norm
    sim_mat = np.dot(normalized_emb, normalized_emb.T)
    sim_df = pd.DataFrame(sim_mat, index=teams, columns=teams)
    sim_df.to_csv(OUTPUT_SIMILARITY)
    print(f"[Embedding Agent] SVD completed. Saved {OUTPUT_EMBEDDINGS} and {OUTPUT_SIMILARITY}.")

def train_pytorch_model(df):
    """Lightweight CPU PyTorch MLP entity embedding model (< 3 seconds on CPU)."""
    import torch
    import torch.nn as nn
    import torch.optim as optim
    
    print("[Embedding Agent] PyTorch detected. Training on CPU engine (torch.device('cpu'))...")
    device = torch.device("cpu")
    
    teams = sorted(list(set(df["home_team"].unique()).union(set(df["away_team"].unique()))))
    team_idx = {t: i for i, t in enumerate(teams)}
    n_teams = len(teams)
    
    class TeamEmbeddingNet(nn.Module):
        def __init__(self, num_teams, emb_dim=16):
            super().__init__()
            self.emb = nn.Embedding(num_teams, emb_dim)
            self.home_bias = nn.Parameter(torch.zeros(1))
            self.fc = nn.Sequential(
                nn.Linear(emb_dim * 2, 8),
                nn.ReLU(),
                nn.Linear(8, 1)
            )
            
        def forward(self, h, a):
            v_h = self.emb(h)
            v_a = self.emb(a)
            x = torch.cat([v_h, v_a], dim=1)
            out = torch.sigmoid(self.fc(x) + self.home_bias)
            return out

    model = TeamEmbeddingNet(n_teams, emb_dim=16).to(device)
    optimizer = optim.Adam(model.parameters(), lr=0.01, weight_decay=1e-4)
    criterion = nn.BCELoss()
    
    h_train = torch.tensor([team_idx[t] for t in df["home_team"]], dtype=torch.long)
    a_train = torch.tensor([team_idx[t] for t in df["away_team"]], dtype=torch.long)
    y_train = torch.tensor(df["home_win"].astype(float).values, dtype=torch.float32).unsqueeze(1)
    
    model.train()
    for epoch in range(120):
        optimizer.zero_grad()
        preds = model(h_train, a_train)
        loss = criterion(preds, y_train)
        loss.backward()
        optimizer.step()
        
    embeddings = model.emb.weight.detach().cpu().numpy()
    emb_df = pd.DataFrame(embeddings, columns=[f"emb_{i+1}" for i in range(16)])
    emb_df.insert(0, "team_id", teams)
    emb_df.to_csv(OUTPUT_EMBEDDINGS, index=False)
    
    # Cosine Similarity
    norm = np.linalg.norm(embeddings, axis=1, keepdims=True) + 1e-8
    norm_emb = embeddings / norm
    sim = np.dot(norm_emb, norm_emb.T)
    pd.DataFrame(sim, index=teams, columns=teams).to_csv(OUTPUT_SIMILARITY)
    print(f"[Embedding Agent] PyTorch training complete. Exported {OUTPUT_EMBEDDINGS} and {OUTPUT_SIMILARITY}.")

def main():
    if not os.path.exists(CSV_TRAIN_SOURCE):
        print(f">>> [WARN] Using SYNTHETIC_FALLBACK: Source file '{CSV_TRAIN_SOURCE}' not found. Generating 1,000 mock game observations...")
        print(f"[Embedding Agent] Warning: Source file {CSV_TRAIN_SOURCE} not found. Generating mock schema...")
        df = pd.DataFrame({
            "home_team": np.random.randint(1, 31, 1000),
            "away_team": np.random.randint(1, 31, 1000),
            "home_win": np.random.choice([True, False], 1000)
        })
    else:
        df = pd.read_csv(CSV_TRAIN_SOURCE)
        
    try:
        import torch
        train_pytorch_model(df)
    except ImportError:
        print("[Embedding Agent] PyTorch is not installed in current Python path.")
        train_embeddings_svd_fallback(df)

if __name__ == "__main__":
    main()