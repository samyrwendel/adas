# <PROJETO> — Registro de Decisões (DA-NNN)

> Log **append-only**. Toda decisão (escolha entre alternativas, trade-off aceito, config com efeito
> permanente, reversão) vira uma entrada numerada, criada por `bash scripts/da-new.sh <escopo> <saga>
> "<título>"` — nunca à mão (o número é max+1 com lock e snapshot). **Numerar sequencial, nunca reusar.**
> Mudar uma decisão = nova DA com `supersede: DA-MMM` (nunca apagar a antiga). Atualizar a faixa
> afetada + regenerar o `ADAS.md` **no mesmo commit**.
>
> Índice: **`DECISIONS-INDEX.md`** — GERADO por `scripts/da-index.sh update` (o hook
> `.claude/hooks/da-index-hook.sh` roda no ato de qualquer edição daqui). Não edite o índice à mão;
> divergência é acusada por `da-index.sh check` e pelo pre-commit. Ler uma DA: `da-index.sh show DA-NNN`.

---

## Protocolo operacional
1. **Quando registrar:** escolha técnica/produto, config permanente, trade-off consciente, reversão —
   **e todo fix aprovado que representa uma CLASSE de erro** (mesmo padrão possível em superfície irmã).
2. **Fix de CLASSE → regra em faixa sensível:** além da DA, a regra é dobrada na faixa que dispara no
   momento certo (`description`/hook) e, se crítica, num check executável (`scripts/check-*.sh`).
   Aprendizado só em chat/doc morto NÃO conta como registrado.
3. **No mesmo commit:** a DA + o índice + a(s) faixa(s) afetada(s) + `ADAS.md` regenerado.
4. **Supersede, não delete.** Número nunca reusado.
5. **Análise de impacto antes de "feito":** callers, schemas, docs, testes, espelhos — e **flagar** o que
   ficou de fora de propósito.

---

## DA-001 — Este projeto adota o ADAS
`escopo: produto` · `saga: —` · `data: <YYYY-MM-DD>` · `refs: —` · `supersede: —`
**Regra:** Toda decisão estrutural deste projeto vira uma entrada DA-NNN neste arquivo, criada por `scripts/da-new.sh`, e nunca é apagada — muda por supersede; o modo declarado em `.adas/profile.json` diz quem aplica a regra (doc: o dono na sessão; mecanismo: só gatilho registrado e testado).
**Motivo:** <PLACEHOLDER: o erro ou a repetição que motivou adotar um diário de decisões agora, neste projeto>
**Trade-off:** Registrar custa minutos por decisão; aceito porque redecidir sem memória custa mais. <PLACEHOLDER: o caso concreto daqui, se houver>
**Lição:** —
**Decidido por:** <PLACEHOLDER: quem decidiu, e a frase literal se houver>
