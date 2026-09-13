# 后端服务目录

后端同学在此目录实现 API、数据库迁移、测试与部署说明。技术语言可自行选择，但对外接口必须实现 `../contracts/openapi.yaml`。

开始前先完成：

1. `POST /api/v1/sessions`
2. `GET /api/v1/sessions/{sessionId}/next`
3. `POST /api/v1/sessions/{sessionId}/events`
4. 事件幂等和 `GET /api/v1/sessions/{sessionId}` 恢复

不要提交数据库密码、LLM Key 或生产地址。复制 `.env.example` 为 `.env` 后再填写本机配置。
