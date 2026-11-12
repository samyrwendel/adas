#!/usr/bin/env python3
"""termostato.py — nível automático do ADAS-JIT (DA-468): sobe por tamanho, risco e violação; desce sem achado.

Sinais (medidos, nada de rede):
  tamanho    DAs no diário: > 50 → nível 2; > 200 → nível 3
  agentes    2+ autores distintos de commit nos repos governados, últimos 30 dias → pelo menos 2
  risco      código versionado que toca dinheiro, cliente ou mensagem a pessoas (pagamento, carteira, envio de
             mensagem/e-mail) → pelo menos 2; junto com 2+ agentes → 3
  violação   achado do juiz ou guard nos últimos 30 dias (juiz-reply.log deny/aviso/guard, copiar-guard deny) → 3.
             Sem achado há 30 dias o sinal some e o nível DESCE para o que os outros sinais pedem.
Fixação manual vence tudo: env ADAS_JIT_NIVEL, ou o arquivo ~/.adas/jit/nivel.fixo (um dígito; o mainbot do Axon
é fixo no 3). Sem fixação, o resultado vai para ~/.adas/jit/nivel, que os hooks leem.
Toda mudança fica no histórico de ~/.adas/jit/termostato.json e sai na revisão semanal (adas-jit-stats.py).

Uso: termostato.py [--home DIR] [--repos a:b] [--agora AAAA-MM-DD] [--json]     (calcula, grava, imprime)
     termostato.py mudancas [--dias 7]                                           (o que mudou na semana)"""
import datetime, glob, json, os, re, subprocess, sys

a = sys.argv[1:]
opt = lambda n, d=None: a[a.index(n) + 1] if n in a else d
HOME = opt("--home", os.path.expanduser("~"))
JD = os.environ.get("ADAS_JIT_DIR") or os.path.join(HOME, ".adas", "jit")
BUS = os.environ.get("ADAS_JIT_BUS") or os.path.join(HOME, ".claude", "bus")
AGORA = datetime.datetime.fromisoformat(opt("--agora")) if opt("--agora") else datetime.datetime.now()
JANELA = 30
RISCO = re.compile(r"(?i)\b(pix|stripe|pagamento|payment|checkout|invoice|fatura|boleto|wallet|carteira|saque|withdraw"
                   r"|sendMessage|send_message|whatsapp|smtp|sendmail|twilio|resend|cliente|customer)\b")


def repos():
    r = opt("--repos")
    if r:
        return [x for x in r.split(":") if x]
    try:
        return [l.strip() for l in open(os.path.join(HOME, ".claude", "adas", "repos.conf"))
                if l.strip() and not l.lstrip().startswith("#")]
    except OSError:
        return []


def n_das():
    try:
        return sum(1 for l in open(os.path.join(HOME, "DECISIONS.md"), encoding="utf-8") if re.match(r"## DA-\d", l))
    except OSError:
        return 0


def git(repo, *c):
    try:
        return subprocess.run(["git", "-C", repo, *c], capture_output=True, text=True, timeout=20).stdout
    except Exception:
        return ""


def agentes(rs):
    desde = (AGORA - datetime.timedelta(days=JANELA)).strftime("%Y-%m-%d")
    nomes = set()
    for r in rs:
        nomes |= {l.strip().lower() for l in git(r, "log", f"--since={desde}", f"--until={AGORA:%Y-%m-%d} 23:59:59", "--format=%an").splitlines() if l.strip()}
    return sorted(nomes)


def risco(rs, teto=4000):
    """Arquivos de código versionados que casam o padrão de dinheiro/cliente/mensagem (amostra: até `teto` por repo)."""
    hits = []
    for r in rs:
        for f in git(r, "ls-files").splitlines()[:teto]:
            if not re.search(r"\.(py|js|ts|mjs|go|rs|rb|php|sh|java|kt)$", f):
                continue
            try:
                if RISCO.search(open(os.path.join(r, f), encoding="utf-8", errors="ignore").read(200000)):
                    hits.append(os.path.join(os.path.basename(r), f))
            except OSError:
                pass
            if len(hits) >= 3:
                return hits
    return hits


def ultimo_achado():
    """Data do achado mais recente do juiz/guard (deny, aviso, guard) — o que mantém o nível 3 por violação."""
    ult = None
    def ver(ts):
        nonlocal ult
        try:
            t = datetime.datetime.fromisoformat(ts[:19].replace(" ", "T"))
        except ValueError:
            return
        if t <= AGORA and (ult is None or t > ult):
            ult = t
    for p in (os.path.join(BUS, "juiz-reply.log"), *glob.glob(os.path.join(HOME, ".hermes*", "governanca", "jit", "jit.log"))):
        try:
            for l in open(p, encoding="utf-8"):
                if re.search(r'"decisao": "(deny|aviso|guard)"', l):
                    m = re.search(r'"ts": "([^"]+)"', l)
                    if m: ver(m.group(1))
        except OSError:
            pass
    try:
        for l in open(os.path.join(BUS, "copiar-guard.log"), encoding="utf-8"):
            if " | deny | " in l: ver(l[:19])
    except OSError:
        pass
    return ult


def calcular():
    rs = repos()
    n, ags, rk, ult = n_das(), agentes(rs), risco(rs), ultimo_achado()
    nivel, motivos = 1, []
    if n > 200:
        nivel = 3; motivos.append(f"{n} DAs (>200)")
    elif n > 50:
        nivel = 2; motivos.append(f"{n} DAs (>50)")
    if len(ags) >= 2:
        nivel = max(nivel, 2); motivos.append(f"{len(ags)} agentes nos repos em {JANELA} d")
    if rk:
        nivel = max(nivel, 2); motivos.append("código toca dinheiro/cliente/mensagem (" + ", ".join(rk[:2]) + ")")
    if rk and len(ags) >= 2:
        nivel = 3
    if ult and (AGORA - ult).days < JANELA:
        nivel = 3; motivos.append(f"achado do juiz/guard em {ult:%d/%m} (< {JANELA} d)")
    return nivel, motivos or ["projeto pequeno, sem risco nem achado"]


def fixado():
    if os.environ.get("ADAS_JIT_NIVEL", "").isdigit():
        return int(os.environ["ADAS_JIT_NIVEL"]), "env ADAS_JIT_NIVEL"
    try:
        v = open(os.path.join(JD, "nivel.fixo")).read().strip()
        if v.isdigit():
            return int(v), "nivel.fixo"
    except OSError:
        pass
    return None, None


def estado():
    try:
        return json.load(open(os.path.join(JD, "termostato.json")))
    except (OSError, ValueError):
        return {"historico": []}


def gravar(st):
    os.makedirs(JD, exist_ok=True)
    tmp = os.path.join(JD, "termostato.json.tmp")
    json.dump(st, open(tmp, "w"), ensure_ascii=False, indent=1); os.replace(tmp, os.path.join(JD, "termostato.json"))


def main():
    if a and a[0] == "mudancas":
        corte = (AGORA - datetime.timedelta(days=int(opt("--dias", "7")))).isoformat(timespec="seconds")
        for h in estado().get("historico", []):
            if h["ts"] >= corte:
                print(f'{h["ts"][:16]} nível {h["de"]} → {h["para"]}: {"; ".join(h["motivos"])}')
        return
    auto, motivos = calcular()
    fx, fonte = fixado()
    efetivo = fx if fx is not None else auto
    st = estado()
    if st.get("efetivo") != efetivo and "efetivo" in st:
        st["historico"].append({"ts": AGORA.isoformat(timespec="seconds"), "de": st["efetivo"], "para": efetivo,
                                "motivos": ([f"fixado por {fonte}"] if fx is not None else []) + motivos})
        st["historico"] = st["historico"][-200:]
    st.update(ts=AGORA.isoformat(timespec="seconds"), automatico=auto, efetivo=efetivo, fixo=fonte, motivos=motivos)
    gravar(st)
    if fx is None:
        tmp = os.path.join(JD, "nivel.tmp")
        open(tmp, "w").write(f"{auto}\n"); os.replace(tmp, os.path.join(JD, "nivel"))
    out = {"nivel": efetivo, "automatico": auto, "fixo": fonte, "motivos": motivos}
    print(json.dumps(out, ensure_ascii=False) if "--json" in a else
          f"nível {efetivo}" + (f" (fixo: {fonte}; o automático daria {auto})" if fonte else "") + " — " + "; ".join(motivos))


if __name__ == "__main__":
    main()
