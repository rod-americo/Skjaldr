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
As credenciais S3 do R2, `APP_API_TOKEN` e `PROFESSIONAL_SIGNATURE` são
instaladas como Worker Secrets. A assinatura exibida na página pública não fica
no código nem no histórico Git. Seu valor local fica em
`~/.local/share/skjaldr-signature.env`, com modo `0600`.

## Provisionamento e deploy

```bash
./Scripts/setup-cloudflare.sh
./Scripts/deploy-cloudflare.sh
./Scripts/test-cloudflare-e2e.sh
```

O setup recusa uma origem A/CNAME existente, outro Worker na raiz, `r2.dev`
habilitado ou domínio público no bucket. MX e TXT são preservados. Migrations
D1 e deploys são repetíveis.

## Página pública

O HTML, CSS e JavaScript do player são gerados pela função `page` em
`Cloudflare/worker/src/index.ts`. A página não é um site separado e não possui
outro repositório ou pipeline.

Depois de alterar a interface pública:

```bash
cd Cloudflare/worker
npm run check
npm test
cd ../..
./Scripts/deploy-cloudflare.sh
./Scripts/test-cloudflare-e2e.sh
```

O deploy atualiza o Worker `skjaldr-video` no Custom Domain já associado, sem
trocar DNS, D1, bucket ou credenciais. O E2E cria um vídeo sintético, valida a
página, Range, revogação e limpeza.

## Variáveis

- `PUBLIC_BASE_URL`: padrão `https://odin.med.br`;
- `CLOUDFLARE_R2_BUCKET`: padrão `skjaldr`;
- `MAX_VIDEO_SIZE_BYTES`: padrão 1 GiB;
- `VIDEO_RETENTION_DAYS`: `0` significa retenção indefinida.
- `ANALYTICS_RETENTION_DAYS`: retenção das estatísticas diárias, padrão 30 dias.

## Estatísticas de acesso

O Worker registra somente totais diários agregados por vídeo:

- visualizações da página;
- reproduções iniciadas;
- reproduções concluídas;
- país;
- classe ampla do dispositivo: `mobile`, `tablet` ou `desktop`.

Não são persistidos IP, `User-Agent`, cidade, coordenadas, sistema operacional,
cookie ou identificador de visitante. Os registros são removidos após 30 dias
por padrão.

A consulta exige o token administrativo:

```text
GET /api/videos/{id}/stats
GET /api/stats?code=123-456
```

O resultado contém totais e a distribuição diária por país e classe de
dispositivo.

Consulta local por código ou URL:

```bash
./Scripts/video-stats.sh 123-456
./Scripts/video-stats.sh https://odin.med.br/123-456
```

Resumo dos 20 vídeos mais recentes:

```bash
./Scripts/video-stats.sh --recent 20
```

O limite pode variar de 1 a 100. O comando apresenta código, status, data de
criação, visualizações, reproduções iniciadas e reproduções concluídas.

## Falhas e recuperação

O MP4 local é a fonte de recuperação. A fila
`~/Library/Application Support/Skjaldr/video-upload-queue.json` preserva a
idempotency key e é retomada na próxima abertura. O botão **Tentar novamente**
reutiliza registro, código e objeto. Registros pendentes por mais de 24 horas
são marcados como falhos pelo Cron.

Antes de criar o recurso remoto, o aplicativo gera ao lado do arquivo local um
derivado oculto H.264 com bitrate-alvo de 3 Mb/s e otimização para início
progressivo. Retries reutilizam o mesmo derivado e a mesma chave de
idempotência. O MP4 bruto permanece recuperável enquanto o upload não for
confirmado. Depois da confirmação, o derivado substitui o bruto no mesmo
caminho; se essa substituição falhar, o bruto é preservado.

Antes de substituir ou remover qualquer arquivo, a fila persiste a URL pública
confirmada e compara tamanho e data de modificação do MP4 com a identidade
registrada no enfileiramento. Assim, um encerramento entre a confirmação e a
promoção local é retomado sem novo upload, e um arquivo trocado externamente
nunca é sobrescrito. A recuperação de capturas reconhece somente temporários
`.skjaldr-<uuid>.mp4`; derivados e backups não são promovidos como gravações.

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
GET    /api/videos/{id}/stats
GET    /api/stats?code=123-456
GET    /api/stats/recent?limit=20
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
