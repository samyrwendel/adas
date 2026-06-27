---
name: seguranca-acesso
description: "Faixa de Segredos & Acesso — governa segredo, token, chave, .env, credencial, e operações de repositório (criar/apagar/mergear/tornar público). Use SEMPRE que a tarefa tocar: token/PAT do GitHub/cloud, chave de API, chave privada, .env/variável de ambiente, credencial, senha, segredo; criar/clonar/apagar repo, abrir/mergear PR, push/force-push, mudar visibilidade ou permissão, deploy key, webhook. Também em sintomas: 'vazou', 'expôs a chave', 'commitei o .env', 'token largo', 'qual permissão', 'tá seguro?'."
when_to_use: "Qualquer tarefa que manuseie segredo/credencial/token, .env, ou faça operação de repositório (criar/apagar/mergear/visibilidade). Enforcement: scripts/check-secrets.sh."
---

# Segredos & Acesso

> Faixa UNIVERSAL (as regras valem em qualquer projeto). Procedência: governança transversal do ADAS;
> complementa a constituição `.specs/`. Fonte da verdade = esta SKILL + `scripts/check-secrets.sh`.
> Caminho crítico = trate como dinheiro.

## Quando se aplica
Token/PAT, chave de API/privada, `.env`, credencial, senha, segredo; e operações de repo (criar/apagar/mergear PR,
push/force-push, mudar visibilidade/permissão, deploy key, webhook). Inclui os sintomas ("vazou", "commitei o .env").

## Leituras obrigatórias (antes de editar)
Ver `references/mandatory-readings.md` — confirmar `.gitignore` cobre `.env`/segredos, e que existe `.env.example` SEM valores.

## Regras — FAÇA
1. **Segredo NUNCA no repo.** `.env`/token/key no `.gitignore`; versionar só `.env.example`/`.env.sample` **sem valores**.
2. **Token least-privilege.** Use **fine-grained** (escopo por repo + só as permissões necessárias: Contents/Pull requests). Nunca PAT clássico amplo (`admin:org`, `delete_repo`, `workflow`) pra um trabalho de push/PR.
3. **Separe segredo de runtime (app `.env`) de segredo de CLI/git.** Não reusar o PAT de automação dentro do `.env` de uma app de produção.
4. **Rotacione ao menor sinal de vazamento** (segredo commitado, logado, colado em chat/PR). Assuma comprometido.
5. **Rode `scripts/check-secrets.sh` antes do commit** (e no deploy). Adote como pré-commit/gate.
6. **`git add <arquivos>` explícito** — nunca `-A`/`.` (varre `.env`/segredo/config sem querer). Mensagem com `Co-Authored-By` se IA.

## Regras — NÃO FAÇA
1. NUNCA commitar/colar/logar `.env`, token, chave privada, senha. NUNCA **imprimir o valor** de um segredo — só mascarado (`<set>`) ou metadado (scopes).
2. NUNCA **vasculhar credencial fora do arquivo/local explicitamente apontado** pelo usuário (não fazer fan-out por `.env`/cofres atrás de token — caça de credencial é violação, mesmo "pra ajudar").
3. NUNCA executar **ação irreversível de repo** — apagar repo, force-push em `main`, tornar público/privado, mudar permissão/colaborador, mergear PR — **sem confirmação explícita do humano**. Criar repo/abrir PR/merge = pede o "sim".
4. NUNCA usar um token amplo quando um fine-grained resolve. NUNCA deixar segredo em URL/query string.

## Trava obrigatória
Antes de qualquer operação de segredo/repo: confirme (a) que não há valor de segredo entrando no repo/log/chat, e (b) que a operação de repo é reversível OU foi explicitamente autorizada nesta conversa. Na dúvida, **pare e pergunte**.
