# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import subprocess

import data_designer.config as dd
from data_designer.interface import DataDesigner


def main() -> None:
    subprocess.run(["data-designer", "--version"], check=True)

    config = dd.DataDesignerConfigBuilder()
    config.add_column(
        dd.SamplerColumnConfig(name="id", sampler_type=dd.SamplerType.UUID, params=dd.UUIDSamplerParams())
    )
    results = DataDesigner().create(config, num_records=3, dataset_name="docker-smoke")
    dataset = results.load_dataset()
    if list(dataset.columns) != ["id"] or len(dataset) != 3 or dataset["id"].nunique() != 3:
        raise RuntimeError("Expected three rows with unique IDs")
    print(f"Verified {len(dataset)} rows in {results.artifact_storage.final_dataset_path}")


if __name__ == "__main__":
    main()
