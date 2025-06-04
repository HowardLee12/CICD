from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/hello")
def say_hello():
    return {"message": "Hello, DevOps World!"}