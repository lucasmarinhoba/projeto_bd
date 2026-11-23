"""
Teste automatizado de concorrencia (Fase 9 - Cenario 3 e Cenario 2).

Executa:
  1) 10 baterias com 20 threads simultaneas sincronizadas por threading.Barrier,
     todas solicitando a mesma sala e horario -> exige exatamente 1 sucesso e 19 RS010.
  2) 1 bateria de corrida no limite de 3 reservas futuras com 10 threads para o mesmo
     usuario em salas distintas -> exige exatamente 1 sucesso (3a reserva) e 9 RS008.
"""

from __future__ import annotations

import os
import sys
import threading
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg

TZ = ZoneInfo("America/Fortaleza")


def load_env() -> dict[str, str]:
    env_path = Path(__file__).resolve().parent.parent / ".env"
    data = dict(os.environ)
    if env_path.exists():
        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            data.setdefault(k.strip(), v.strip())
    return data


def build_conninfo(env: dict[str, str], use_app_role: bool) -> str:
    host = env.get("POSTGRES_HOST", "127.0.0.1")
    port = env.get("POSTGRES_PORT", "5433")
    dbname = env.get("POSTGRES_DB", "reservas")
    if use_app_role:
        user = env.get("APP_DB_USER", "app_reservas")
        password = env.get("APP_DB_PASSWORD", "app_reservas_dev_password")
    else:
        user = env.get("POSTGRES_USER", "postgres")
        password = env.get("POSTGRES_PASSWORD", "postgres_dev_password")
    return f"host={host} port={port} dbname={dbname} user={user} password={password}"


def resolve_worker_conninfo(env: dict[str, str]) -> tuple[str, str]:
    """Usa app_reservas quando disponivel (Fase 10+); caso contrario usa POSTGRES_USER."""
    admin_dsn = build_conninfo(env, use_app_role=False)
    app_user = env.get("APP_DB_USER", "app_reservas")
    try:
        with psycopg.connect(admin_dsn) as conn:
            row = conn.execute(
                """
                SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = %s)
                   AND has_function_privilege(
                         %s,
                         'reservas.criar_reserva(bigint,integer,timestamptz,timestamptz,integer,text)',
                         'EXECUTE'
                       )
                """,
                (app_user, app_user),
            ).fetchone()
            if row and row[0]:
                return build_conninfo(env, use_app_role=True), app_user
    except psycopg.Error:
        pass
    return admin_dsn, env.get("POSTGRES_USER", "postgres")


def pick_usuarios_livres(admin_dsn: str, quantidade: int) -> list[int]:
    """Seleciona usuarios ativos nao-admin sem reservas futuras (evita RS008 acidental)."""
    with psycopg.connect(admin_dsn) as conn:
        rows = conn.execute(
            """
            SELECT u.id
            FROM reservas.usuario u
            WHERE u.ativo
              AND u.tipo <> 'ADMIN'
              AND NOT EXISTS (
                SELECT 1
                FROM reservas.reserva r
                WHERE r.usuario_id = u.id
                  AND r.status = 'ATIVA'
                  AND lower(r.periodo) > now()
              )
            ORDER BY u.id
            LIMIT %s
            """,
            (quantidade,),
        ).fetchall()
    if len(rows) < quantidade:
        raise RuntimeError(
            f"Necessarios {quantidade} usuarios sem reservas futuras; encontrados {len(rows)}."
        )
    return [int(r[0]) for r in rows]


def run_cenario_3(admin_dsn: str, worker_dsn: str, worker_role: str) -> None:
    print(f"=== Cenario 3: 10 baterias x 20 threads (role={worker_role}) ===")
    n_threads = 20
    n_baterias = 10
    base_date = datetime.now(TZ).date() + timedelta(days=60)

    for bateria in range(1, n_baterias + 1):
        usuarios = pick_usuarios_livres(admin_dsn, n_threads)
        dia_slot = base_date + timedelta(days=bateria)
        ini = datetime.combine(dia_slot, datetime.min.time(), tzinfo=TZ) + timedelta(hours=14)
        fim = ini + timedelta(hours=2)

        barrier = threading.Barrier(n_threads)
        resultados: list[tuple[int, str, int | str]] = []
        lock = threading.Lock()

        def worker(idx: int, uid: int) -> None:
            try:
                with psycopg.connect(worker_dsn, autocommit=False) as conn:
                    conn.execute("SET search_path = reservas, public;")
                    conn.execute("SET timezone = 'America/Fortaleza';")
                    barrier.wait(timeout=15)
                    try:
                        res = conn.execute(
                            "SELECT criar_reserva(%s, %s, %s, %s, %s, %s)",
                            (uid, 5, ini, fim, 10, f"Concorrencia B{bateria} T{idx}"),
                        ).fetchone()
                        conn.commit()
                        with lock:
                            resultados.append((idx, "OK", int(res[0])))
                    except psycopg.Error as exc:
                        conn.rollback()
                        with lock:
                            resultados.append((idx, exc.sqlstate or "ERR", exc.diag.message_primary or str(exc)))
            except Exception as exc:  # pragma: no cover - erro inesperado de barreira/conexao
                with lock:
                    resultados.append((idx, "EXC", str(exc)))

        threads = [
            threading.Thread(target=worker, args=(i, usuarios[i]), daemon=True)
            for i in range(n_threads)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=30)

        sucessos = [r for r in resultados if r[1] == "OK"]
        conflitos = [r for r in resultados if r[1] == "RS010"]
        outros = [r for r in resultados if r[1] not in ("OK", "RS010")]

        assert len(resultados) == n_threads, f"Bateria {bateria}: faltaram respostas ({len(resultados)})"
        assert len(outros) == 0, f"Bateria {bateria}: erros inesperados: {outros}"
        assert len(sucessos) == 1, f"Bateria {bateria}: esperado 1 sucesso, obtido {len(sucessos)}"
        assert len(conflitos) == n_threads - 1, (
            f"Bateria {bateria}: esperado {n_threads - 1} RS010, obtido {len(conflitos)}"
        )

        with psycopg.connect(admin_dsn) as conn:
            qtd_banco = conn.execute(
                """
                SELECT count(*)
                FROM reservas.reserva
                WHERE sala_id = 5
                  AND status = 'ATIVA'
                  AND periodo && tstzrange(%s, %s, '[)')
                """,
                (ini, fim),
            ).fetchone()[0]
        assert qtd_banco == 1, f"Bateria {bateria}: banco ficou com {qtd_banco} reservas sobrepostas!"
        print(
            f"  Bateria {bateria:02d}/10 OK: 1 sucesso (reserva_id={sucessos[0][2]}), "
            f"19 RS010, sobrepostas no banco={qtd_banco}"
        )


def run_cenario_2_limite(admin_dsn: str, worker_dsn: str) -> None:
    print("=== Cenario 2 (automatizado): corrida no limite de 3 reservas futuras ===")
    uid = pick_usuarios_livres(admin_dsn, 1)[0]
    base_date = datetime.now(TZ).date() + timedelta(days=90)

    # Cria 2 reservas futuras previas para o usuario (em dias/salas distintos)
    with psycopg.connect(admin_dsn, autocommit=False) as conn:
        for k in range(2):
            d = base_date + timedelta(days=k)
            ini = datetime.combine(d, datetime.min.time(), tzinfo=TZ) + timedelta(hours=8)
            fim = ini + timedelta(hours=2)
            conn.execute(
                "SELECT reservas.criar_reserva(%s, %s, %s, %s, %s, %s)",
                (uid, 1 + k, ini, fim, 10, f"Previa limite {k + 1}"),
            )
        conn.commit()

    # Dispara 10 threads simultaneas tentando criar a 3a reserva em salas diferentes (1..10, dia diferente)
    n_threads = 10
    barrier = threading.Barrier(n_threads)
    resultados: list[tuple[int, str]] = []
    lock = threading.Lock()
    d_corrida = base_date + timedelta(days=5)

    def worker(idx: int) -> None:
        ini = datetime.combine(d_corrida, datetime.min.time(), tzinfo=TZ) + timedelta(hours=10)
        fim = ini + timedelta(hours=2)
        sala_id = 1 + idx  # salas 1..10 (sem conflito de sala entre as threads)
        with psycopg.connect(worker_dsn, autocommit=False) as conn:
            conn.execute("SET search_path = reservas, public;")
            conn.execute("SET timezone = 'America/Fortaleza';")
            barrier.wait(timeout=15)
            try:
                conn.execute(
                    "SELECT criar_reserva(%s, %s, %s, %s, %s, %s)",
                    (uid, sala_id, ini, fim, 5, f"Corrida limite T{idx}"),
                )
                conn.commit()
                with lock:
                    resultados.append((idx, "OK"))
            except psycopg.Error as exc:
                conn.rollback()
                with lock:
                    resultados.append((idx, exc.sqlstate or "ERR"))

    threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(n_threads)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)

    sucessos = sum(1 for _, st in resultados if st == "OK")
    erros_rs008 = sum(1 for _, st in resultados if st == "RS008")
    assert sucessos == 1, f"Corrida limite: esperado 1 sucesso, obtido {sucessos} ({resultados})"
    assert erros_rs008 == n_threads - 1, (
        f"Corrida limite: esperado {n_threads - 1} RS008, obtido {erros_rs008} ({resultados})"
    )

    with psycopg.connect(admin_dsn) as conn:
        total_futuras = conn.execute(
            """
            SELECT count(*)
            FROM reservas.reserva
            WHERE usuario_id = %s AND status = 'ATIVA' AND lower(periodo) > now()
            """,
            (uid,),
        ).fetchone()[0]
    assert total_futuras == 3, f"Usuario {uid} ficou com {total_futuras} reservas futuras!"
    print(f"  Corrida limite OK: usuario {uid} -> 1 sucesso, 9 RS008, total futuras={total_futuras}")


def main() -> int:
    env = load_env()
    admin_dsn = build_conninfo(env, use_app_role=False)
    worker_dsn, worker_role = resolve_worker_conninfo(env)
    run_cenario_3(admin_dsn, worker_dsn, worker_role)
    run_cenario_2_limite(admin_dsn, worker_dsn)
    print("TODOS OS TESTES DE CONCORRENCIA PASSARAM.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
