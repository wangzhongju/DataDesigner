# DataDesigner Docker 部署

部署目录为 92 服务器上的 `/home/cdky/workspace/github/DataDesigner`。构建需要带 Git 历史和标签的检出目录、Docker BuildKit 和 Docker Compose 2.24 或更新版本。镜像使用 Ubuntu 24.04 和 Python 3.12，从当前源码和 `uv.lock` 安装三个 workspace 包。

## 构建和启动

```bash
cd /home/cdky/workspace/github/DataDesigner
bash docker/docker.sh build prod datadesigner-local:latest
bash docker/docker.sh start
```

默认镜像标签为 `datadesigner-local:latest`。如果构建了 `datadesigner-local:v2`，在启动前执行 `export DATA_DESIGNER_IMAGE=datadesigner-local:v2` 选择该镜像。首次构建下载依赖，后续构建复用 Docker 层和 uv 缓存。

## 通过 SSH 隧道下载

在运行 HTTP 代理的 Windows 工作站上打开 PowerShell。以下命令将工作站的 `127.0.0.1:7897` 转发到 92 服务器的 `127.0.0.1:17897`，构建期间保持该窗口运行。

```powershell
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -R 127.0.0.1:17897:127.0.0.1:7897 cdky@192.168.88.92
```

另开一个 SSH 会话，在 92 上执行构建。

```bash
cd /home/cdky/workspace/github/DataDesigner
SSH_TUNNEL_ENABLED=1 bash docker/docker.sh build prod datadesigner-local:latest
```

如需更换服务器端口，同步修改 `ssh -R` 的监听端口和 92 上的 `SSH_TUNNEL_PROXY`。可在构建命令前传入该变量，也可把 `docker/config/build.env.example` 复制到 `docker/env/build.env` 后修改。脚本先通过隧道检查 PyPI，再让构建步骤通过 host 网络访问回环代理。apt 软件包和 Python 依赖走该代理。基础镜像 `ubuntu:24.04` 由 Docker daemon 获取，92 已有本地缓存。构建完成即可关闭本地 SSH 隧道。

92 的构建配置使用 `UBUNTU_ARCHIVE_URL=http://mirrors.huaweicloud.com/ubuntu/`。重新部署时可将其写入 `docker/env/build.env`，也可在构建命令前传入。apt 仍会校验 Ubuntu 软件仓库的签名。

## 在容器内使用

在宿主机执行 `bash docker/docker.sh into` 进入容器。宿主机的工程根目录挂载到容器的 `/workspace`，也是进入容器时的工作目录。镜像提供 `make`、`git` 和 `uv`，可按工程说明安装源码并验证导入。 [工程 README](../README.md)

```bash
make install
make verify-imports
```

`uv` 使用容器用户可写的 `/opt/venv`。宿主机的 `.venv` 可用于宿主机自己的 Python 环境。重新创建容器后，如需继续以可编辑模式使用挂载源码，再执行 `make install`。

退出交互 Shell 后，可从宿主机直接运行容器命令。下面的验收脚本会检查 CLI，再用 UUID 采样器生成并读回三行 Parquet 数据。

```bash
bash docker/docker.sh status
bash docker/docker.sh exec data-designer --help
bash docker/docker.sh exec python - < docker/scripts/verify.py
# 将 generate.py 和所需输入放在工程根目录后执行
bash docker/docker.sh exec python generate.py
bash docker/docker.sh stop
```

`start` 保持容器运行，供 `into` 和 `exec` 使用。构建新镜像或修改运行配置后，执行 `bash docker/docker.sh recreate` 应用更新。

默认生成结果写入容器的 `/workspace/artifacts/`，对应宿主机工程根目录的 `artifacts/`。CLI 配置保存在 `docker/state/.data-designer/`。

## 容器账户和 Bash 配置

`docker/runtime/env.sh` 按启动命令的宿主机用户配置容器账户，用户名、主组、UID 和 GID 保持一致。92 上以 `cdky` 启动时，容器 HOME 为 `/home/cdky`，对应宿主机 `docker/home/cdky/`。在 `into` 打开的 Bash 中，提示符沿用 RAGFlow 的配色，用户名为绿色，容器主机名为紫色，当前目录为青色。

首次初始化时生成 `.bashrc`、`.profile`、`.datadesigner_env` 和 `.vimrc`。可在 `docker/home/cdky/.bashrc` 自定义 `PS1`，后续进入、重启和重建容器都会读取该文件。容器账户可使用 `sudo`、`vim` 和 Bash 补全。

## 配置模型服务

工程 README 中的 LLM 预览需要模型服务的 API 密钥。默认示例使用 `nvidia-text`，在 92 上创建运行配置并填入 `NVIDIA_API_KEY`。

```bash
mkdir -p docker/env
(umask 077 && cp -n docker/config/app.env.example docker/env/app.env)
```

`docker/env/app.env` 在创建容器时加载。在 `into` 打开的 Bash 中运行 `data-designer config providers` 可交互配置模型服务。

92 上的 `scripts/test.py` 通过 `qwen-text` 别名调用百炼。百炼的密钥填入 `docker/env/app.env` 的 `DASHSCOPE_API_KEY`，保存后执行 `bash docker/docker.sh recreate`。

`docker/state/.data-designer/model_providers.yaml` 保存服务方和接入地址。模型的别名、服务方和平台模型 ID 在同目录的 `model_configs.yaml` 配置。92 配置了以下别名，列通过 `model_alias` 选择。

| 别名 | 模型 ID | 用途 |
| --- | --- | --- |
| `qwen-text` | `qwen3.8-flash` | 文本生成、结构化输出和判断 |
| `qwen-vision` | `qwen3.8-flash` | 带图片上下文的文本生成 |
| `qwen-embedding` | `qwen3.7-text-embedding-flash` | 1024 维文本向量 |
