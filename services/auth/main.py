import os
from datetime import datetime, timedelta, timezone
import jwt
from pwdlib import PasswordHash
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sqlalchemy import Integer, String, select
from sqlalchemy.orm import Mapped, mapped_column
from common.core import Base, Session, initialize, SECRET

app = FastAPI(title='Authentication Service')
password_hash = PasswordHash.recommended()
class User(Base):
    __tablename__ = 'users'
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(80), unique=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(20))
    student_id: Mapped[int | None] = mapped_column(Integer, nullable=True)

@app.on_event('startup')
def start():
    initialize()
    with Session() as db:
        for username, password, role, sid in [('admin',os.environ['DEMO_ADMIN_PASSWORD'],'admin',None),('student1',os.environ['DEMO_STUDENT_PASSWORD'],'student',1)]:
            if not db.scalar(select(User).where(User.username==username)):
                db.add(User(username=username,hashed_password=password_hash.hash(password),role=role,student_id=sid))
        db.commit()

class Login(BaseModel):
    username: str
    password: str

@app.post('/login')
def login(body: Login):
    with Session() as db:
        user=db.scalar(select(User).where(User.username==body.username))
        if not user or not password_hash.verify(body.password,user.hashed_password):
            raise HTTPException(401,'Invalid username or password')
        claims={'sub':user.username,'role':user.role,'student_id':user.student_id,'exp':datetime.now(timezone.utc)+timedelta(hours=8)}
        token=jwt.encode(claims,SECRET,algorithm='HS256')
        return {'access_token':token,'role':user.role,'username':user.username,'student_id':user.student_id}

@app.get('/health')
def health(): return {'status':'ok','service':'auth'}
