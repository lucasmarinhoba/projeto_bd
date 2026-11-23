"""Aplicacao principal (CLI interativa, servidor web simples e --smoke-test)."""

from __future__ import annotations

import argparse
import sys
import threading
import urllib.parse
import urllib.request
from datetime import date, timedelta
from http.server import ThreadingHTTPServer

from db import (
    SQL_AGENDA_DIA,
    SQL_CANCELAR_RESERVA,
    SQL_CRIAR_RESERVA,
    SQL_OCUPACAO_MENSAL,
    SQL_SALAS_RECURSOS,
    chamar,
    conectar,
    parse_data,
    parse_data_hora,
    parse_mes,
)
from web import ReservaHandler, iniciar_servidor


def menu_agenda(conn) -> None:
    try:
        sala_id = int(input("ID da sala: ").strip())
        dia = parse_data(input("Dia (YYYY-MM-DD): "))
    except ValueError as exc:
        print(f"✖ Formato invalido: {exc}")
        return
    linhas = chamar(conn, SQL_AGENDA_DIA, (sala_id, dia))
    if linhas is None:
        return
    if not linhas:
        print("(Sem reservas ativas para esta sala neste dia)")
        return
    print("ID    | Inicio   | Fim      | Responsavel                  | Finalidade | Qtd")
    for r in linhas:
        print(f"{r[0]:<5} | {str(r[1])[:8]} | {str(r[2])[:8]} | {r[3]:<28} | {r[4] or '-':<10} | {r[5]}")


def menu_criar(conn) -> None:
    try:
        usuario_id = int(input("ID do usuario: ").strip())
        sala_id = int(input("ID da sala: ").strip())
        dia_str = input("Data (YYYY-MM-DD): ").strip()
        h_ini = input("Hora inicio (HH:MM): ").strip()
        h_fim = input("Hora fim (HH:MM): ").strip()
        qtd = int(input("Quantidade de participantes: ").strip())
        finalidade = input("Finalidade (opcional): ").strip() or None
        inicio = parse_data_hora(dia_str, h_ini)
        fim = parse_data_hora(dia_str, h_fim)
    except ValueError as exc:
        print(f"✖ Formato invalido: {exc}")
        return
    linhas = chamar(conn, SQL_CRIAR_RESERVA, (usuario_id, sala_id, inicio, fim, qtd, finalidade))
    if linhas:
        print(f"✔ Reserva criada com ID = {linhas[0][0]}")


def menu_cancelar(conn) -> None:
    try:
        reserva_id = int(input("ID da reserva: ").strip())
        usuario_id = int(input("ID do usuario (dono ou ADMIN): ").strip())
        motivo = input("Motivo do cancelamento (opcional): ").strip() or None
    except ValueError as exc:
        print(f"✖ Formato invalido: {exc}")
        return
    res = chamar(conn, SQL_CANCELAR_RESERVA, (reserva_id, usuario_id, motivo))
    if res is not None:
        print(f"✔ Reserva {reserva_id} cancelada.")


def menu_ocupacao(conn) -> None:
    try:
        mes = parse_mes(input("Mes (YYYY-MM): "))
    except ValueError as exc:
        print(f"✖ Formato invalido: {exc}")
        return
    linhas = chamar(conn, SQL_OCUPACAO_MENSAL, (mes,))
    if linhas is None:
        return
    print("Sala   | Reservas | Horas  | Ocupacao (%)")
    for r in linhas:
        print(f"{r[0]:<6} | {r[1]:<8} | {str(r[2]):<6} | {r[3]}%")


def menu_salas(conn) -> None:
    linhas = chamar(conn, SQL_SALAS_RECURSOS)
    if not linhas:
        return
    for r in linhas:
        print(f"[{r[0]:>2}] {r[1]:<6} | {r[2]:<30} | {r[3]:<11} | {r[4]} lug. | {r[6]}")


def run_cli() -> int:
    with conectar() as conn:
        while True:
            print("\n=== Sistema de Reserva de Salas ===")
            print("1. Agenda da sala no dia")
            print("2. Criar reserva")
            print("3. Cancelar reserva")
            print("4. Relatorio de ocupacao mensal")
            print("5. Listar salas e recursos (apoio)")
            print("6. Iniciar pagina web (http://127.0.0.1:8000)")
            print("0. Sair")
            op = input("Opcao: ").strip()
            if op == "1":
                menu_agenda(conn)
            elif op == "2":
                menu_criar(conn)
            elif op == "3":
                menu_cancelar(conn)
            elif op == "4":
                menu_ocupacao(conn)
            elif op == "5":
                menu_salas(conn)
            elif op == "6":
                iniciar_servidor()
            elif op == "0":
                return 0
            else:
                print("Opcao invalida.")


def run_smoke_test() -> int:
    print("=== Smoke Test E2E (CLI + Web) como app_reservas ===")
    dia = date.today() + timedelta(days=3)
    dia_str = dia.isoformat()
    mes = date.today().replace(day=1)

    criadas: list[int] = []
    with conectar() as conn:
        try:
            info = chamar(conn, "SELECT current_user, current_setting('TimeZone')")
            assert info and info[0][0] == "app_reservas", f"Role inesperada: {info}"
            assert info[0][1] == "America/Fortaleza", f"Timezone inesperado: {info}"
            print(f"OK sessao: user={info[0][0]}, tz={info[0][1]}")

            # 1) Criar reserva valida na sala 5 para o usuario 1
            r1 = chamar(
                conn,
                SQL_CRIAR_RESERVA,
                (1, 5, parse_data_hora(dia_str, "14:00"), parse_data_hora(dia_str, "16:00"), 15, "Smoke E2E"),
            )
            assert r1 and r1[0][0] > 0, "Falha ao criar reserva valida"
            rid1 = int(r1[0][0])
            criadas.append(rid1)
            print(f"OK criar_reserva: id={rid1}")

            # 2) Ver na agenda (v_agenda_dia)
            ag1 = chamar(conn, SQL_AGENDA_DIA, (5, dia))
            assert ag1 and any(row[0] == rid1 for row in ag1), f"Reserva {rid1} nao apareceu na agenda"
            print(f"OK v_agenda_dia: reserva {rid1} encontrada")

            # 3) Provocar erros RS005..RS010 e RS012 vindos direto do banco
            print("-- Provocando erros do banco via app (mensagens repassadas): --")
            # RS005 (menos de 30 min)
            assert chamar(
                conn, SQL_CRIAR_RESERVA,
                (1, 5, parse_data_hora(dia_str, "08:00"), parse_data_hora(dia_str, "08:15"), 10, "RS005"),
            ) is None
            # RS006 (antes das 07:00)
            assert chamar(
                conn, SQL_CRIAR_RESERVA,
                (1, 5, parse_data_hora(dia_str, "06:30"), parse_data_hora(dia_str, "08:00"), 10, "RS006"),
            ) is None
            # RS007 (acima de 40 lugares na sala 5)
            assert chamar(
                conn, SQL_CRIAR_RESERVA,
                (1, 5, parse_data_hora(dia_str, "08:00"), parse_data_hora(dia_str, "10:00"), 99, "RS007"),
            ) is None
            # RS010 (conflito com 14h-16h na sala 5)
            assert chamar(
                conn, SQL_CRIAR_RESERVA,
                (2, 5, parse_data_hora(dia_str, "15:00"), parse_data_hora(dia_str, "17:00"), 10, "RS010"),
            ) is None
            # RS008 (atinge 3 futuras no usuario 1 e falha na 4a)
            r2 = chamar(
                conn, SQL_CRIAR_RESERVA,
                (1, 5, parse_data_hora(dia_str, "08:00"), parse_data_hora(dia_str, "10:00"), 10, "Extra 2"),
            )
            r3 = chamar(
                conn, SQL_CRIAR_RESERVA,
                (1, 5, parse_data_hora(dia_str, "10:00"), parse_data_hora(dia_str, "12:00"), 10, "Extra 3"),
            )
            assert r2 and r3
            criadas.extend([int(r2[0][0]), int(r3[0][0])])
            assert chamar(
                conn, SQL_CRIAR_RESERVA,
                (1, 5, parse_data_hora(dia_str, "16:00"), parse_data_hora(dia_str, "18:00"), 10, "RS008"),
            ) is None
            # RS012 (usuario 2 tentando cancelar reserva do usuario 1)
            assert chamar(conn, SQL_CANCELAR_RESERVA, (rid1, 2, "Sem permissao")) is None

            # 4) Cancelar todas as reservas criadas e verificar sumico da agenda
            for rid in list(criadas):
                assert chamar(conn, SQL_CANCELAR_RESERVA, (rid, 1, "Limpeza smoke")) is not None
                criadas.remove(rid)
            ag2 = chamar(conn, SQL_AGENDA_DIA, (5, dia))
            assert ag2 is not None and not any(row[0] == rid1 for row in ag2), "Reserva cancelada ainda na agenda!"
            print("OK cancelar_reserva: reservas canceladas e removidas de v_agenda_dia")

            # 5) Relatorio de ocupacao mensal
            oc = chamar(conn, SQL_OCUPACAO_MENSAL, (mes,))
            assert oc and len(oc) == 20, f"Esperado 20 salas no relatorio, obtido {len(oc) if oc else 0}"
            print(f"OK mv_ocupacao_mensal: {len(oc)} salas listadas para {mes.strftime('%Y-%m')}")
        finally:
            for rid in criadas:
                chamar(conn, SQL_CANCELAR_RESERVA, (rid, 1, "Limpeza smoke finally"))

    # 6) Smoke test da interface web em porta efemera
    srv = ThreadingHTTPServer(("127.0.0.1", 0), ReservaHandler)
    port = srv.server_address[1]
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/?sala_id=5&dia={dia_str}", timeout=5) as resp:
            html_get = resp.read().decode("utf-8")
            assert resp.status == 200
            assert "Sistema de Reserva de Salas e Laboratórios" in html_get
            assert "app_reservas" in html_get
            assert "1. Agenda da Sala no Dia" in html_get
            assert "4. Relatório de Ocupação Mensal" in html_get

        payload = urllib.parse.urlencode(
            {
                "usuario_id": "1",
                "sala_id": "5",
                "dia": dia_str,
                "hora_inicio": "14:00",
                "hora_fim": "16:00",
                "qtd": "99",  # deve acionar RS007 vindo do banco e renderizar no banner
                "finalidade": "Web Smoke",
                "mes": mes.strftime("%Y-%m"),
            }
        ).encode("utf-8")
        req = urllib.request.Request(f"http://127.0.0.1:{port}/criar", data=payload, method="POST")
        with urllib.request.urlopen(req, timeout=5) as resp:
            html_post = resp.read().decode("utf-8")
            assert resp.status == 200
            assert "RS007" in html_post and "✖" in html_post
        print(f"OK web.py: GET / e POST /criar renderizaram pagina HTML e erro RS007 do banco (porta {port})")
    finally:
        srv.shutdown()
        srv.server_close()

    print("SMOKE TEST FASE 11 PASSOU.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Sistema de Reserva de Salas")
    parser.add_argument("--web", action="store_true", help="Inicia a pagina web em http://127.0.0.1:8000")
    parser.add_argument("--smoke-test", action="store_true", help="Executa verificacao ponta a ponta")
    args = parser.parse_args()

    if args.smoke_test:
        return run_smoke_test()
    if args.web:
        iniciar_servidor()
        return 0
    return run_cli()


if __name__ == "__main__":
    sys.exit(main())
