# Security Policy

## Supported Versions

Security fixes are applied to the latest released major version of AaronDB.

| Version | Supported |
|---|---|
| 3.x | Yes |
| < 3.0 | No |

## Reporting a Vulnerability

Please **do not** open a public issue for a suspected vulnerability.

Report it privately to the MoneyAcademyKE maintainers through GitHub's private security advisory workflow for this repository. Include:

- a clear description of the issue and affected AaronDB versions;
- a minimal reproduction or proof of concept where safe to share;
- potential impact and any suggested mitigation.

You should receive an acknowledgement within seven days. Maintainers will investigate, coordinate a fix, and agree on disclosure timing before a public advisory is published.

## Security Boundaries

AaronDB currently supports an **embedded library plus local stdio MCP** deployment boundary. It does not provide an HTTP/TCP listener, remote identity verification, signed bearer tokens, or a distributed HA guarantee.

Treat persisted Erlang-term data as trusted only when it originates from a controlled AaronDB store. AaronDB uses safe decoding for its own serialized rules, but operators remain responsible for filesystem permissions, backups, and persistence-layer access control.

Mnesia support is recovery-oriented. An incompatible existing `datoms` schema causes initialization to fail without rewriting data; migrate or reset it explicitly after taking a backup.

For current limitations on sharding, Raft, and Mnesia, see the project ADRs and feature maturity documentation.
