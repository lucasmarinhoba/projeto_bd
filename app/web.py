"""Interface web minima (stdlib http.server) sem frameworks e sem regras de negocio."""

from __future__ import annotations

import html
from datetime import date, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from db import (
    cancelar_reserva_existente,
    conectar,
    criar_nova_reserva,
    listar_agenda_dia,
    listar_salas,
    parse_data,
    parse_data_hora,
    parse_mes,
    relatorio_ocupacao_mensal,
)

HOST = "127.0.0.1"
PORT = 8000


def esc(val: object) -> str:
    return html.escape("" if val is None else str(val), quote=True)


def render_page(
    sala_id: int,
    dia: date,
    mes: date,
    banner: tuple[str, str] | None = None,
) -> str:
    hoje_mais_2 = (date.today() + timedelta(days=2)).isoformat()
    with conectar() as conn:
        ok_ag, agenda_rows, err_ag, _ = listar_agenda_dia(conn, sala_id, dia)
        ok_oc, ocup_rows, err_oc, _ = relatorio_ocupacao_mensal(conn, mes)
        ok_sl, salas_rows, err_sl, _ = listar_salas(conn)
        info_row = conn.execute("SELECT current_user, current_setting('TimeZone')").fetchone()

    role_atual = info_row[0] if info_row else "app_reservas"
    tz_atual = info_row[1] if info_row else "America/Fortaleza"

    banner_html = ""
    if banner:
        tipo, texto = banner
        cls = "alert-ok" if tipo == "ok" else "alert-err"
        banner_html = f'<div class="alert {cls}">{esc(texto)}</div>'

    if ok_ag:
        if agenda_rows:
            ag_body = "".join(
                f"<tr><td>#{esc(r[0])}</td><td>{esc(str(r[1])[:5])} - {esc(str(r[2])[:5])}</td>"
                f"<td>{esc(r[3])}</td><td>{esc(r[4] or '-')}</td><td>{esc(r[5])}</td></tr>"
                for r in agenda_rows
            )
        else:
            ag_body = '<tr><td colspan="5" class="muted">Nenhuma reserva ativa para esta sala neste dia.</td></tr>'
    else:
        ag_body = f'<tr><td colspan="5" class="err-cell">{esc(err_ag)}</td></tr>'

    if ok_oc:
        oc_body = "".join(
            f"<tr><td><strong>{esc(r[0])}</strong></td><td>{esc(r[1])}</td>"
            f"<td>{esc(r[2])} h</td><td>{esc(r[3])}%</td></tr>"
            for r in ocup_rows
        )
    else:
        oc_body = f'<tr><td colspan="4" class="err-cell">{esc(err_oc)}</td></tr>'

    if ok_sl:
        opts_list = []
        for r in salas_rows:
            sel_attr = ' selected' if r[0] == sala_id else ''
            opts_list.append(
                f'<option value="{esc(r[0])}"{sel_attr}>'
                f'{esc(r[0])} - {esc(r[1])} ({esc(r[4])} lug.)</option>'
            )
        salas_opts = "".join(opts_list)
        salas_body = "".join(
            f"<tr><td>{esc(r[0])}</td><td><strong>{esc(r[1])}</strong></td><td>{esc(r[2])}</td>"
            f"<td>{esc(r[3])}</td><td>{esc(r[4])}</td><td class='muted'>{esc(r[6])}</td></tr>"
            for r in salas_rows
        )
    else:
        salas_opts = f'<option value="{esc(sala_id)}">Sala {esc(sala_id)}</option>'
        salas_body = f'<tr><td colspan="6" class="err-cell">{esc(err_sl)}</td></tr>'

    mes_str = mes.strftime("%Y-%m")
    dia_str = dia.isoformat()

    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Sistema de Reserva de Salas e Laboratórios</title>
  <style>
    :root {{ --bg:#f8fafc; --card:#ffffff; --bd:#e2e8f0; --pri:#1e3a8a; --txt:#0f172a; --mut:#475569; }}
    * {{ box-sizing:border-box; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; }}
    body {{ margin:0; background:var(--bg); color:var(--txt); padding:24px; }}
    .wrap {{ max-width:1200px; margin:0 auto; }}
    header {{ display:flex; flex-wrap:wrap; justify-content:space-between; align-items:center; gap:12px; margin-bottom:20px; }}
    h1 {{ margin:0; font-size:1.5rem; color:var(--pri); }}
    .badge {{ background:#dbeafe; color:#1e40af; padding:6px 12px; border-radius:999px; font-size:0.85rem; font-weight:600; }}
    .alert {{ padding:14px 16px; border-radius:10px; margin-bottom:18px; font-weight:600; border:1px solid; }}
    .alert-ok {{ background:#dcfce7; color:#166534; border-color:#86efac; }}
    .alert-err {{ background:#fee2e2; color:#991b1b; border-color:#fca5a5; }}
    .grid {{ display:grid; grid-template-columns:repeat(auto-fit, minmax(340px, 1fr)); gap:18px; margin-bottom:22px; }}
    .card {{ background:var(--card); border:1px solid var(--bd); border-radius:12px; padding:18px; box-shadow:0 1px 3px rgba(0,0,0,.04); }}
    .card h2 {{ margin:0 0 12px; font-size:1.1rem; color:var(--pri); }}
    label {{ display:block; font-size:0.85rem; font-weight:600; color:var(--mut); margin-top:10px; }}
    input, select {{ width:100%; padding:8px 10px; margin-top:4px; border:1px solid #cbd5e1; border-radius:8px; font-size:0.95rem; }}
    .row2 {{ display:grid; grid-template-columns:1fr 1fr; gap:10px; }}
    button {{ margin-top:14px; padding:9px 14px; background:var(--pri); color:#fff; border:none; border-radius:8px; cursor:pointer; font-weight:600; width:100%; }}
    button.danger {{ background:#b91c1c; }}
    button:hover {{ opacity:0.92; }}
    table {{ width:100%; border-collapse:collapse; margin-top:12px; font-size:0.88rem; }}
    th, td {{ text-align:left; padding:8px 6px; border-bottom:1px solid var(--bd); }}
    th {{ color:var(--mut); font-weight:600; }}
    .muted {{ color:var(--mut); }}
    .err-cell {{ color:#b91c1c; font-weight:600; }}
    .scroll {{ max-height:320px; overflow:auto; }}
  </style>
</head>
<body>
<div class="wrap">
  <header>
    <div>
      <h1>Sistema de Reserva de Salas e Laboratórios</h1>
      <div class="muted" style="font-size:0.9rem;">Aplicação "casca fina" — todas as regras são executadas no PostgreSQL</div>
    </div>
    <div class="badge">role: {esc(role_atual)} · tz: {esc(tz_atual)}</div>
  </header>

  {banner_html}

  <div class="grid">
    <section class="card">
      <h2>1. Agenda da Sala no Dia (<code>v_agenda_dia</code>)</h2>
      <form method="get" action="/">
        <input type="hidden" name="mes" value="{esc(mes_str)}" />
        <label>Sala
          <select name="sala_id">{salas_opts}</select>
        </label>
        <label>Dia
          <input type="date" name="dia" value="{esc(dia_str)}" required />
        </label>
        <button type="submit">Consultar Agenda</button>
      </form>
      <div class="scroll">
        <table>
          <thead><tr><th>ID</th><th>Horário</th><th>Responsável</th><th>Finalidade</th><th>Qtd</th></tr></thead>
          <tbody>{ag_body}</tbody>
        </table>
      </div>
    </section>

    <section class="card">
      <h2>2. Criar Reserva (<code>criar_reserva</code>)</h2>
      <form method="post" action="/criar">
        <div class="row2">
          <label>ID Usuário
            <input type="number" name="usuario_id" value="1" required />
          </label>
          <label>Sala
            <select name="sala_id">{salas_opts}</select>
          </label>
        </div>
        <label>Data
          <input type="date" name="dia" value="{esc(hoje_mais_2)}" required />
        </label>
        <div class="row2">
          <label>Início (HH:MM)
            <input type="time" name="hora_inicio" value="14:00" required />
          </label>
          <label>Fim (HH:MM)
            <input type="time" name="hora_fim" value="16:00" required />
          </label>
        </div>
        <div class="row2">
          <label>Qtd. Participantes
            <input type="number" name="qtd" value="20" required />
          </label>
          <label>Finalidade
            <input type="text" name="finalidade" placeholder="Aula / Monitoria" />
          </label>
        </div>
        <input type="hidden" name="mes" value="{esc(mes_str)}" />
        <button type="submit">Solicitar Reserva</button>
      </form>
      <p class="muted" style="font-size:0.8rem; margin-top:10px;">
        Demo: ID 1 e 2 = Alunos · ID 3 = Professor · ID 4 = Admin · Sala 5 = Demo A-105 (40 lug.)
      </p>
    </section>

    <section class="card">
      <h2>3. Cancelar Reserva (<code>cancelar_reserva</code>)</h2>
      <form method="post" action="/cancelar">
        <label>ID da Reserva
          <input type="number" name="reserva_id" required placeholder="Ex.: 13241" />
        </label>
        <label>ID do Usuário Solicitante (dono ou ADMIN)
          <input type="number" name="usuario_id" value="1" required />
        </label>
        <label>Motivo do Cancelamento
          <input type="text" name="motivo" placeholder="Opcional" />
        </label>
        <input type="hidden" name="sala_id" value="{esc(sala_id)}" />
        <input type="hidden" name="dia" value="{esc(dia_str)}" />
        <input type="hidden" name="mes" value="{esc(mes_str)}" />
        <button type="submit" class="danger">Cancelar Reserva</button>
      </form>
    </section>
  </div>

  <section class="card" style="margin-bottom:22px;">
    <h2>4. Relatório de Ocupação Mensal (<code>mv_ocupacao_mensal</code>)</h2>
    <form method="get" action="/" style="display:flex; gap:12px; align-items:end; max-width:420px;">
      <input type="hidden" name="sala_id" value="{esc(sala_id)}" />
      <input type="hidden" name="dia" value="{esc(dia_str)}" />
      <label style="flex:1; margin:0;">Mês (YYYY-MM)
        <input type="month" name="mes" value="{esc(mes_str)}" required />
      </label>
      <button type="submit" style="width:auto; margin:0;">Gerar Relatório</button>
    </form>
    <div class="scroll">
      <table>
        <thead><tr><th>Sala</th><th>Reservas Ativas</th><th>Horas Reservadas</th><th>Taxa de Ocupação</th></tr></thead>
        <tbody>{oc_body}</tbody>
      </table>
    </div>
  </section>

  <section class="card">
    <h2>Catálogo de Salas e Recursos (<code>v_salas_recursos</code>)</h2>
    <div class="scroll">
      <table>
        <thead><tr><th>ID</th><th>Código</th><th>Nome</th><th>Tipo</th><th>Lugares</th><th>Recursos</th></tr></thead>
        <tbody>{salas_body}</tbody>
      </table>
    </div>
  </section>
</div>
</body>
</html>"""


class ReservaHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        return

    def _send_html(self, content: str, status: int = 200) -> None:
        raw = content.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:
        qs = parse_qs(urlparse(self.path).query)
        try:
            sala_id = int(qs.get("sala_id", ["5"])[0])
        except ValueError:
            sala_id = 5
        try:
            dia = parse_data(qs.get("dia", [date.today().isoformat()])[0])
        except ValueError:
            dia = date.today()
        try:
            mes = parse_mes(qs.get("mes", [date.today().strftime("%Y-%m")])[0])
        except ValueError:
            mes = date.today().replace(day=1)

        html_out = render_page(sala_id=sala_id, dia=dia, mes=mes)
        self._send_html(html_out)

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        form = {k: v[0] for k, v in parse_qs(body, keep_blank_values=True).items()}

        try:
            sala_id = int(form.get("sala_id", "5"))
        except ValueError:
            sala_id = 5
        try:
            dia = parse_data(form.get("dia", date.today().isoformat()))
        except ValueError:
            dia = date.today()
        try:
            mes = parse_mes(form.get("mes", date.today().strftime("%Y-%m")))
        except ValueError:
            mes = date.today().replace(day=1)

        banner: tuple[str, str] | None = None

        if self.path == "/criar":
            try:
                usuario_id = int(form.get("usuario_id", ""))
                qtd = int(form.get("qtd", ""))
                inicio = parse_data_hora(form.get("dia", ""), form.get("hora_inicio", ""))
                fim = parse_data_hora(form.get("dia", ""), form.get("hora_fim", ""))
                finalidade = form.get("finalidade", "")
                with conectar() as conn:
                    ok, rows, msg, sqlstate = criar_nova_reserva(
                        conn, usuario_id, sala_id, inicio, fim, qtd, finalidade
                    )
                if ok and rows:
                    banner = ("ok", f"✔ Reserva #{rows[0][0]} criada com sucesso no PostgreSQL!")
                else:
                    prefixo = f"[{sqlstate}] " if sqlstate else ""
                    banner = ("err", f"✖ {prefixo}{msg}")
            except ValueError as exc:
                banner = ("err", f"✖ Formato de entrada invalido: {exc}")

        elif self.path == "/cancelar":
            try:
                reserva_id = int(form.get("reserva_id", ""))
                usuario_id = int(form.get("usuario_id", ""))
                motivo = form.get("motivo", "")
                with conectar() as conn:
                    ok, _, msg, sqlstate = cancelar_reserva_existente(
                        conn, reserva_id, usuario_id, motivo
                    )
                if ok:
                    banner = ("ok", f"✔ Reserva #{reserva_id} cancelada com sucesso!")
                else:
                    prefixo = f"[{sqlstate}] " if sqlstate else ""
                    banner = ("err", f"✖ {prefixo}{msg}")
            except ValueError as exc:
                banner = ("err", f"✖ Formato de entrada invalido: {exc}")

        html_out = render_page(sala_id=sala_id, dia=dia, mes=mes, banner=banner)
        self._send_html(html_out)


def iniciar_servidor(host: str = HOST, port: int = PORT) -> None:
    server = ThreadingHTTPServer((host, port), ReservaHandler)
    print(f"Servidor web ativo em http://{host}:{port} (Ctrl+C para encerrar)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServidor encerrado.")
    finally:
        server.server_close()


if __name__ == "__main__":
    iniciar_servidor()
