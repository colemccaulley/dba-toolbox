# Blocking Incident Response

1. Run `performance/blocking-check.sql` while the incident is happening.
2. Identify the head blocker and the blocked session count.
3. Capture login, host, database, wait type, wait duration, and query text.
4. Prefer application/session owner escalation before killing a session.
5. If a kill is required, record the SPID, transaction context, and business approval.
6. After the incident, review missing indexes, long transactions, isolation level, and Query Store regressions.
