"""Camada fina de acesso ao PostgreSQL (apenas driver psycopg 3 + SQL parametrizado)."""

from __future__ import annotations

import os
from datetime import date, datetime, time
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import psycopg

TZ = ZoneInfo("America/Fortaleza")

SQL_AGENDA_DIA = (
    "SELECT reserva_id, hora_inicio, hora_fim, responsavel, finalidade, qtd_participantes "
    "FROM v_agenda_dia WHERE sala_id = %s AND dia = %s ORDER BY hora_inicio"
)
SQL_CRIAR_RESERVA = "SELECT criar_reserva(%s, %s, %s, %s, %s, %s)"
SQL_CANCELAR_RESERVA = "SELECT cancelar_reserva(%s, %s, %s)"
SQL_OCUPACAO_MENSAL = (
    "SELECT sala_codigo, total_reservas, horas_reservadas, taxa_ocupacao_pct "
    "FROM mv_ocupacao_mensal WHERE mes = %s ORDER BY taxa_ocupacao_pct DESC, sala_codigo"
)
SQL_SALAS_RECURSOS = (
    "SELECT sala_id, codigo, nome, tipo, capacidade, ativa, recursos "
    "FROM v_salas_recursos ORDER BY sala_id"
)


def carregar_env() -> dict[str, str]:
    env_path = Path(__file__).resolve().parent.parent / ".env"
    data = dict(os.environ)
    if env_path.exists():
        for raw in env_path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            data.setdefault(k.strip(), v.strip())
    return data


def conectar() -> psycopg.Connection:
    """Conecta exclusivamente como a role restrita app_reservas."""
    env = carregar_env()
    host = env.get("POSTGRES_HOST", "127.0.0.1")
    port = env.get("POSTGRES_PORT", "5433")
    dbname = env.get("POSTGRES_DB", "reservas")
    user = env.get("APP_DB_USER", "app_reservas")
    password = env.get("APP_DB_PASSWORD", "app_reservas_dev_password")
    return psycopg.connect(
        host=host,
        port=port,
        dbname=dbname,
        user=user,
        password=password,
        autocommit=False,
    )


def executar_sql(
    conn: psycopg.Connection, sql: str, params: tuple[Any, ...] = ()
) -> tuple[bool, list[tuple[Any, ...]], str | None, str | None]:
    """Executa SQL parametrizado, faz commit no sucesso e rollback + captura mensagem do banco no erro."""
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            linhas = cur.fetchall() if cur.description else []
        conn.commit()
        return True, linhas, None, None
    except psycopg.Error as e:
        conn.rollback()
        msg = e.diag.message_primary or str(e).splitlines()[0]
        return False, [], msg, e.sqlstate


def chamar(conn: psycopg.Connection, sql: str, params: tuple[Any, ...] = ()) -> list[tuple[Any, ...]] | None:
    """Wrapper CLI que executa e imprime o erro vindo do banco sem tratar regra alguma."""
    ok, linhas, msg, sqlstate = executar_sql(conn, sql, params)
    if not ok:
        prefixo = f"[{sqlstate}] " if sqlstate else ""
        print(f"✖ {prefixo}{msg}")
        return None
    return linhas


def parse_data(texto: str) -> date:
    """Converte YYYY-MM-DD para date (apenas formato)."""
    return date.fromisoformat(texto.strip())


def parse_mes(texto: str) -> date:
    """Converte YYYY-MM (ou YYYY-MM-DD) para o 1o dia do mes."""
    t = texto.strip()
    if len(t) == 7:
        return date.fromisoformat(f"{t}-01")
    return date.fromisoformat(t).replace(day=1)


def parse_data_hora(dia_str: str, hora_str: str) -> datetime:
    """Converte data + hora (HH:MM) para timestamptz no fuso America/Fortaleza."""
    d = parse_data(dia_str)
    h = time.fromisoformat(hora_str.strip())
    return datetime.combine(d, h, tzinfo=TZ)


def listar_agenda_dia(conn: psycopg.Connection, sala_id: int, dia: date):
    return executar_sql(conn, SQL_AGENDA_DIA, (sala_id, dia))


def criar_nova_reserva(
    conn: psycopg.Connection,
    usuario_id: int,
    sala_id: int,
    inicio: datetime,
    fim: datetime,
    qtd: int,
    finalidade: str | None,
):
    fin = finalidade.strip() if finalidade and finalidade.strip() else None
    return executar_sql(conn, SQL_CRIAR_RESERVA, (usuario_id, sala_id, inicio, fim, qtd, fin))


def cancelar_reserva_existente(
    conn: psycopg.Connection, reserva_id: int, usuario_id: int, motivo: str | None
):
    mot = motivo.strip() if motivo and motivo.strip() else None
    return executar_sql(conn, SQL_CANCELAR_RESERVA, (reserva_id, usuario_id, mot))


def relatorio_ocupacao_mensal(conn: psycopg.Connection, mes: date):
    return executar_sql(conn, SQL_OCUPACAO_MENSAL, (mes,))


def listar_salas(conn: psycopg.Connection):
    return executar_sql(conn, SQL_SALAS_RECURSOS)
