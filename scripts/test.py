# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import os

import data_designer.config as dd
from data_designer.interface import DataDesigner


def main() -> None:
    if not os.getenv("DASHSCOPE_API_KEY", "").strip():
        raise SystemExit("Set DASHSCOPE_API_KEY in the container before running this script.")

    data_designer = DataDesigner()
    config_builder = dd.DataDesignerConfigBuilder()

    # Add a product category
    config_builder.add_column(
        dd.SamplerColumnConfig(
            name="product_category",
            sampler_type=dd.SamplerType.CATEGORY,
            params=dd.CategorySamplerParams(
                values=["Electronics", "Clothing", "Home & Kitchen", "Books"],
            ),
        )
    )

    # Generate personalized customer reviews
    config_builder.add_column(
        dd.LLMTextColumnConfig(
            name="review",
            model_alias="qwen-text",
            prompt="Write a brief product review for a {{ product_category }} item you recently purchased.",
        )
    )

    # Preview your dataset
    # preview = data_designer.preview(config_builder=config_builder)
    # preview.display_sample_record()

    preview = data_designer.preview(
        config_builder=config_builder,
        num_records=5,
    )

    for index in range(len(preview.dataset)):
        preview.display_sample_record(index=index)


if __name__ == "__main__":
    main()
