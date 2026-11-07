# 卡密数据备份

备份时间：2026-11-07
来源：腾讯云 COS 桶 `626c-blushing-locust-d5fzu75r8866e882-1304789126`（ap-shanghai），前缀 `bindings/`

## 内容

| 文件 | 说明 |
|---|---|
| `_keys.json` | 全部卡密名单，149 条（永久 51 / 月卡 98），含档位 |
| `_all.json` | 全部绑定记录，62 条，格式 `{ "bindings/<卡密>.json": { 记录 } }` |
| `<卡密>.json` | 单条绑定记录，与 COS 中的对象一一对应 |

## 单条记录字段

```json
{
  "deviceId": "设备指纹（Keychain 中的 UUID）",
  "plan": "forever | month",
  "activatedAt": "首次激活时间 ISO8601",
  "expiresAt": "到期时间；永久卡为 null",
  "released": "可选，管理端解绑标记"
}
```

## 恢复方式

迁移到其他服务端（如 Cloudflare KV、自建服务）时，把 `_all.json` 的每个键值对
原样写入目标存储即可，key 去掉 `bindings/` 前缀与 `.json` 后缀。

注意：`deviceId` 是客户端 Keychain 里的 UUID，卸载重装 App 不会变；
只有抹机、恢复备份到新设备时才会变。
