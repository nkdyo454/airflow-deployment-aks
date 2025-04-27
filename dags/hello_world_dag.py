from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

def hello_world():
    print("Hello world from Airflow!")

with DAG(
    dag_id="hello_world_dag",
    start_date=datetime(2025, 4, 27),
    schedule_interval=None,
    catchup=False,
    tags=["test"],
) as dag:
    task = PythonOperator(
        task_id="say_hello",
        python_callable=hello_world,
    )
