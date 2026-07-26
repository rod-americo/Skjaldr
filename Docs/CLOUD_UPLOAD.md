# Operação do upload Cloudflare

## Arquitetura

```text
Skjaldr ── POST /api/videos ──> Worker ──> D1
   │                               │
   ├── PUT pré-assinado ─────────> R2 privado
   └── POST /complete ───────────> valida tamanho/checksum

odin.med.br/123-456 ──> Worker ──> D1 ── stream Range ──> R2
```

## Credenciais e permissões

O token bootstrap fica em `~/.local/share/cloudflare-r2.env`. O comando
`bootstrap-cloudflare.sh` cria `skjaldr-production` com:

- conta: Account Settings Read, Workers Scripts Write, D1 Write e Workers R2
  Storage Write;
- zona `odin.med.br`: Zone Read, DNS Read/Write e Workers Routes Read/Write.

O token dedicado fica em `~/.local/share/skjaldr-cloudflare.env`, modo `0600`.
As credenciais S3 do R2 e `APP_API_TOKEN` são instaladas como Worker Secrets.

## Provisionamento e deploy

```bash
./Scripts/setup-cloudflare.sh
./Scripts/deploy-cloudflare.sh
./Scripts/test-cloudflare-e2e.sh
```

O setup recusa uma origem A/CNAME existente, outro Worker na raiz, `r2.dev`
habilitado ou domínio público no bucket. MX e TXT são preservados. Migrations
D1 e deploys são repetíveis.

## Variáveis

- `PUBLIC_BASE_URL`: padrão `https://odin.med.br`;
- `CLOUDFLARE_R2_BUCKET`: padrão `skjaldr`;
- `MAX_VIDEO_SIZE_BYTES`: padrão 1 GiB;
- `VIDEO_RETENTION_DAYS`: `0` significa retenção indefinida.

## Falhas e recuperação

O MP4 local é a fonte de recuperação. A fila
`~/Library/Application Support/Skjaldr/video-upload-queue.json` preserva a
idempotency key e é retomada na próxima abertura. O botão **Tentar novamente**
reutiliza registro, código e objeto. Registros pendentes por mais de 24 horas
são marcados como falhos pelo Cron.

Para observar:

```bash
cd Cloudflare/worker
npx wrangler tail --config wrangler.generated.jsonc
```

Logs contêm IDs técnicos e eventos, nunca conteúdo clínico.

## Revogação e exclusão

Rotas administrativas exigem `Authorization: Bearer`:

```text
POST   /api/videos/{id}/revoke
DELETE /api/videos/{id}
GET    /api/videos/{id}/status
```

Revogar mantém o objeto e torna a página indisponível. Excluir remove o objeto
e mantém o registro como tombstone; códigos nunca são reutilizados.

## Retenção

Com `VIDEO_RETENTION_DAYS > 0`, novos registros recebem `expires_at` e o Cron
diário remove o objeto depois da expiração. Lifecycle direto do R2 permanece
desativado para impedir divergência entre objeto e D1.

## Rotação

1. Crie ou rotacione o token pela Cloudflare.
2. Atualize o arquivo local protegido.
3. Execute `setup-cloudflare.sh` para reinstalar secrets.
4. Rode o E2E antes de revogar a credencial anterior.

Para o token do app, remova `cloud-upload.json`, execute o setup e publique
novamente. Instâncias antigas deixam de conseguir usar a API.

## Backup

- R2 é a cópia remota dos vídeos; o arquivo local continua sendo mantido por
  padrão.
- D1 oferece recuperação gerenciada; exportações operacionais podem ser feitas
  com `wrangler d1 export`.
- Guarde fora do Git os dois arquivos de ambiente e documente sua rotação.
