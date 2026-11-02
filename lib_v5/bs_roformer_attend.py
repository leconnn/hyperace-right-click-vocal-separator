"""Attention primitive used by the bundled BS-Roformer HyperACE model.

The upstream model imports this helper from a larger package.  Keeping the
small, dependency-free implementation here makes the copied model runnable in
this standalone UVR/right-click distribution.
"""

from __future__ import annotations

import torch.nn.functional as F
from torch import nn


class Attend(nn.Module):
    """Multi-head scaled dot-product attention with optional dropout."""

    def __init__(self, dropout: float = 0.0, flash: bool = True, **_: object):
        super().__init__()
        self.dropout = dropout
        self.flash = flash

    def forward(self, queries, keys, values):
        # PyTorch selects the best available CUDA kernel (including Flash
        # Attention when supported) for this operation.
        return F.scaled_dot_product_attention(
            queries,
            keys,
            values,
            dropout_p=self.dropout if self.training else 0.0,
        )
