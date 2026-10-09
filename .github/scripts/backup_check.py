#!/usr/bin/env python3
"""Сверка бэкапа базы: сколько строк в каждой таблице дампа и столько ли их после восстановления.

    backup_check.py counts data.sql    — «схема.таблица|строк» по блокам COPY дампа
    backup_check.py sql data.sql       — SQL, который считает строки тех же таблиц в базе

Считаем по самому дампу, а не по рабочей базе: та меняется, пока идёт дамп. Печатает только имена
таблиц и числа — логи репозитория публичные.
"""

import re
import sys

COPY = re.compile(r'^COPY ("[^"]+"\."[^"]+") \(.*\) FROM stdin;$')


def counts(path):
    result = {}
    table = None
    with open(path, encoding="utf-8") as dump:
        for line in dump:
            if table is None:
                match = COPY.match(line.rstrip("\n"))
                if match:
                    table, rows = match.group(1), 0
            elif line.rstrip("\n") == "\\.":
                result[table] = rows
                table = None
            else:
                rows += 1
    return result


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("counts", "sql"):
        sys.exit(__doc__)
    tables = counts(sys.argv[2])
    if not tables:
        sys.exit("В дампе нет ни одного блока COPY — дамп пустой или битый")
    if sys.argv[1] == "counts":
        for name in sorted(tables):
            print(f"{name}|{tables[name]}")
    else:
        parts = [f"select '{name}' || '|' || count(*) from {name}" for name in sorted(tables)]
        print("\nunion all\n".join(parts) + "\norder by 1;")


if __name__ == "__main__":
    main()
