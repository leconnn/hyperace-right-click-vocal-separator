"""Attention primitive used by the bundled BS-RoFormer HyperACE model."""

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
        return F.scaled_dot_product_attention(
            queries,
            keys,
            values,
            dropout_p=self.dropout if self.training else 0.0,
        )
