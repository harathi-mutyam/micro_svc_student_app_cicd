# Student Management Microservices — Docker Compose Demo

Separate **PHP frontend**, **FastAPI Authentication**, **Student**, **Attendance**, and **Marks** services. An NGINX gateway routes requests. Four separate MySQL databases share one MySQL server for this learning demo.

## Start on an Ubuntu EC2 with Docker + Compose installed

```bash
unzip student-microservices-complete.zip
cd student-microservices-complete
cp .env.example .env
python3 -c 'import secrets; print(secrets.token_hex(32))'
nano .env    # set JWT_SECRET to generated hex string; change all demo passwords

docker compose config
docker compose up -d --build
docker compose ps
docker compose logs --tail=100
curl http://127.0.0.1:8080/api/auth/health
curl http://127.0.0.1:8080/api/students/health
curl http://127.0.0.1:8080/api/attendance/health
curl http://127.0.0.1:8080/api/marks/health
```

From Windows Git Bash, open a **second terminal** and connect with a local tunnel:

```bash
ssh -i ~/Downloads/YOUR_KEY.pem -L 8080:127.0.0.1:8080 ubuntu@YOUR_EC2_PUBLIC_IP
```

Open **http://localhost:8080** on Windows. Do not open port 8080 publicly in the EC2 Security Group.

## Demo login

- Admin: `admin` / password you set as `DEMO_ADMIN_PASSWORD` in `.env`
- Student: `student1` / password you set as `DEMO_STUDENT_PASSWORD` in `.env`

Demo student ID **1** is seeded. The demo student can view their own record, attendance and marks; admin can create/update/delete student records, and add/delete attendance and marks. Update APIs are also provided for attendance and marks, but edit forms are not yet in the UI.

## Important caveats

- This is a **new, functional learning prototype**, not a pixel-exact or schema-compatible conversion of the original PHP repository. It does not import the old database or reproduce every original page.
- **Creating additional student records does not automatically create login accounts**. Only the seeded `student1` has a student login in this version.
- Each service has its own database, but a common MySQL server. The database users are demo-only fixed credentials in Compose/init SQL. Change these consistently before deployment to a real shared network.
- Authentication uses signed JWTs; frontend keeps the token in a server-side PHP session; requests use backend role checks. For production add account provisioning, token revocation, secure HTTPS, stricter validation, database migrations, structured authorization and business integrity checks.
- Because service databases are isolated, attendance/marks are currently not validating student IDs against Student Service; this is a known learning-prototype limitation to fix before production.
- Running `docker compose down -v` **permanently deletes all demo database data**.
- Don't commit `.env` or credentials to GitHub. Change all demo credentials before use.
- No EKS, Argo CD, CI/CD, Prometheus or Loki is configured in this ZIP; test the application first.

## Architecture

Browser → NGINX Gateway → PHP UI / Auth API / Student API / Attendance API / Marks API. Each API reads only its own MySQL database.

## Test admin API directly

```bash
TOKEN=$(curl -sf http://127.0.0.1:8080/api/auth/login \
-H 'Content-Type: application/json' \
-d '{"username":"admin","password":"YOUR_ADMIN_PASSWORD"}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8080/api/students/
```
