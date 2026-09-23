# ERPNext v16 on LoongArch

这是一套可在龙芯环境中构建和运行的 ERPNext v16 Compose
部署。构建与运行均使用原生 `linux/loong64` 镜像

当前默认版本：

- ERPNext `v16.35.0`
- Frappe `v16.34.0`
- Python 3.14 / Node.js 24
- MariaDB 11.8 / Redis 7.4

## 宿主机要求

- 采用龙芯新世界的发行版（这里仅对AOSC OS承诺兼容性）
- Docker Compose

## 快速开始

```bash
git clone https://github.com/WeiguangTWK/erpnext_docker_loongarch --depth=1
cd ./erpnext_docker_loongarch
chmod +x erpnext-loongarch.sh
./erpnext-loongarch.sh up
```

第一次执行会自动完成：

1. 生成权限为 `0600` 的 `.env` 和包含其中的随机密码；
2. 在镜像构建阶段生成 `mysqlclient` wheel，会存放在/opt/loongarch-wheels；
3. 从 LoongArch Python 镜像源下载 DuckDB wheel；
4. 安装 Rollup、Lightning CSS、Tailwind Oxide 的 LoongArch 原生模块；
5. 构建 Frappe、ERPNext 和 Banking 前端资产；
6. 拉取原生 MariaDB、Redis 镜像；
7. 创建站点、安装 ERPNext 并启用 Scheduler；
8. 启动后端、Nginx、WebSocket、Worker 和 Scheduler。

所有 wheel 都在构建阶段写入 `/opt/loongarch-wheels`，随后复制到
最终镜像

默认访问地址为 `http://HOST_IP:8080`，用户名为 `Administrator`。查看自动
生成的管理员密码：

```bash
./erpnext-loongarch.sh password
```

## 常用命令

```bash
./erpnext-loongarch.sh init      # 仅生成 .env
./erpnext-loongarch.sh build     # 构建并执行镜像冒烟测试
./erpnext-loongarch.sh up        # 启动或更新完整服务
./erpnext-loongarch.sh verify    # 检查应用、Worker、Scheduler 和 HTTP
./erpnext-loongarch.sh status    # 查看状态
./erpnext-loongarch.sh logs      # 跟踪日志
./erpnext-loongarch.sh down      # 停止服务并保留持久卷
```

## 修改部署参数

第一次启动前可编辑 `.env`：

```dotenv
SITE_NAME=frontend
HTTP_PORT=8080
GUNICORN_WORKERS=2
GUNICORN_THREADS=4
```

构建版本可通过环境变量覆盖：

```bash
FRAPPE_VERSION=v16.34.0 \
ERPNEXT_VERSION=v16.35.0 \
./erpnext-loongarch.sh build
```

原生依赖版本也可通过 `MYSQLCLIENT_VERSION`、`DUCKDB_VERSION`、
`BANKING_VITE_VERSION`、`BANKING_REACT_PLUGIN_VERSION`、
`LIGHTNINGCSS_LOONG64_VERSION` 和 `TAILWIND_OXIDE_LOONG64_VERSION` 覆盖。

## （重要）持久数据

Compose 使用 `db-data`、`redis-queue-data`、`sites` 和 `logs` 四个命名卷。
`down` 命令不会删除这些卷。放心使用 :)

## 同步 frappe_docker 资源

入口脚本和 Nginx 配置来自 `frappe/frappe_docker`。上游 revision 固定在
`upstream/frappe_docker.commit`，本地 LoongArch 修改保存在独立补丁中。

检查当前文件是否与“固定 revision + 补丁”一致：

```bash
./scripts/sync-frappe-docker.sh --check
```

重新拉取并同步涉及Docker容器的容器内脚本，并应用适配补丁：

```bash
./scripts/sync-frappe-docker.sh
```

这些派生文件继续保留上游 MIT 许可和版权声明，详情见
`THIRD-PARTY-NOTICES.md` 与 `LICENSES/frappe_docker-MIT.txt`。
