# Deploy Codex WebUI cho nhóm nội bộ

Cấu hình này dùng **một Codex profile**, nhiều conversation và một workspace
chung. Owner có thể thay tài khoản ChatGPT khi tài khoản hiện tại hết quota;
conversation và file vẫn được giữ trong cùng `CODEX_HOME`.

## Mô hình dữ liệu

```text
./data/codex  -> /home/node/.codex -> auth, config, skills, sessions
./data/webui -> /data             -> queue, upload, metadata, audit log
./workspace  -> /workspace        -> project và ảnh của cả nhóm
```

Đây là mô hình dành cho nhóm tin cậy. Thành viên dùng chung profile có thể thấy
conversation và file của nhau. Owner password cần được giữ riêng vì owner có
quyền terminal và các thao tác cấp host. Theo quy ước vận hành, chỉ owner nên
đổi tài khoản; phiên bản upstream hiện vẫn cho admin gọi luồng account login,
nên đây chưa phải một giới hạn được backend cưỡng chế.

## 1. Chuẩn bị

```bash
cp .env.docker.example .env
mkdir -p data/codex data/webui workspace
sudo chown -R 1000:1000 data workspace
docker network inspect nginx_network >/dev/null || \
  docker network create nginx_network
docker compose build
```

Bạn cũng có thể đổi tên thay vì copy:

```bash
mv .env.docker.example .env
```

## 2. Hoàn thiện `.env`

Tạo hai password hash khác nhau:

```bash
docker run --rm --entrypoint node codex-webui:local \
  /app/scripts/hash-password.mjs 'MAT_KHAU_CHO_THANH_VIEN'

docker run --rm --entrypoint node codex-webui:local \
  /app/scripts/hash-password.mjs 'MAT_KHAU_OWNER_RIENG'
```

Tạo session secret:

```bash
openssl rand -base64 48
```

Trong `.env`, thay đúng bốn giá trị:

```dotenv
CODEX_WEBUI_PUBLIC_ORIGIN=https://codex.example.com
CODEX_WEBUI_PASSWORD_HASH='scrypt$...'
CODEX_WEBUI_OWNER_PASSWORD_HASH='scrypt$...'
CODEX_WEBUI_SESSION_SECRET=...
```

Giữ hash trong dấu nháy đơn để ký tự `$` không bị Docker Compose nội suy. Không
commit `.env` hoặc `data/codex/auth.json`.

Kiểm tra cấu hình trước khi chạy:

```bash
docker compose config >/dev/null
```

## 3. Khởi động và đăng nhập ChatGPT lần đầu

```bash
docker compose up -d
docker compose ps
docker compose logs -f --tail=100 codex-webui
```

Đăng nhập bằng giao diện WebUI là cách được khuyến nghị: owner mở Account hoặc
Settings, chọn ChatGPT login và hoàn tất OAuth/device code.

Nếu cần đăng nhập từ terminal của Ubuntu server:

```bash
docker compose run --rm --entrypoint codex \
  codex-webui login --device-auth
```

Kiểm tra tài khoản hiện tại:

```bash
docker compose run --rm --entrypoint codex \
  codex-webui login status
```

## 4. Đổi tài khoản nhưng giữ conversation

Credential và conversation cùng nằm dưới `./data/codex`, nhưng là các dữ liệu
khác nhau. Đăng nhập tài khoản mới sẽ thay `auth.json`; session/rollout không bị
xóa. WebUI tự đóng app-server của profile để request tiếp theo đọc credential
mới, nên không cần restart container.

Quy trình an toàn:

1. owner thông báo tạm dừng gửi prompt;
2. kiểm tra không còn active turn và session queue;
3. logout tài khoản hiện tại trong Account/Settings;
4. login tài khoản ChatGPT mới trong cùng profile;
5. kiểm tra tên tài khoản và quota mới;
6. mở lại conversation cũ và tiếp tục.

Nếu thay tài khoản khi một turn đang chạy, app-server có thể bị đóng và turn đó
có thể lỗi. Việc đổi tài khoản ảnh hưởng toàn bộ conversation trong instance.

## 5. Cách chia workspace

Nên tạo thư mục riêng cho từng người hoặc từng dự án:

```text
/workspace/
├── user-01/
├── user-02/
├── marketing/
│   ├── references/
│   └── outputs/
└── shared-assets/
```

Khi yêu cầu tạo ảnh, ghi rõ đường dẫn output, ví dụ
`/workspace/marketing/outputs`. WebUI có thể hiển thị generated-image cards,
nhưng khả năng tạo ảnh phụ thuộc tài khoản, Codex CLI và ImageGen skill/tool
đang khả dụng trong Catalog/Settings.

## 6. Tài nguyên và concurrency

Thiết lập mặc định cho mô hình dùng chung:

```dotenv
CODEX_WEBUI_PER_SESSION_APP_SERVERS=false
CODEX_WEBUI_MAX_APP_SERVERS=auto
```

Conversation không chạy đồng thời có thể dùng runtime chính của profile. Khi
nhiều turn chạy cùng lúc, WebUI tạo thêm app-server nếu còn CPU/RAM. Chế độ
`auto` dành khoảng 2 GiB cho mỗi app-server, chừa khoảng 1 GiB cho gateway/hệ
thống và tự giới hạn tối đa 4 process. App-server không hoạt động được thu hồi
sau 300 giây.

Giới hạn 10 GB chỉ áp dụng cho attachment storage do WebUI quản lý. Dữ liệu lưu
trực tiếp trong `/workspace` không bị giới hạn, vì vậy cần theo dõi dung lượng
ổ đĩa và backup định kỳ.

## 7. Reverse proxy Nginx

Service không publish port ra host. Nginx trong `nginx_network` truy cập bằng
hostname `codex-webui`, port `4173`:

```nginx
server {
    listen 443 ssl http2;
    server_name codex.example.com;

    # ssl_certificate ...;
    # ssl_certificate_key ...;

    client_max_body_size 60m;

    location / {
        proxy_pass http://codex-webui:4173;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }
}
```

Với Nginx Proxy Manager:

- Forward Hostname: `codex-webui`
- Forward Port: `4173`
- bật Websockets Support và SSL
- đặt `client_max_body_size 60m` trong phần Advanced nếu cần upload ảnh lớn

## 8. Backup và cập nhật

Backup đầy đủ:

```text
data/codex
data/webui
workspace
.env
```

Cập nhật ứng dụng:

```bash
git pull --ff-only
docker compose build --pull
docker compose up -d
```

Không chạy nhiều replica dùng chung các volume này. Gateway và app-server giữ
state cục bộ nên deployment phải là single-instance.
