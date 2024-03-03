from diagrams import Cluster, Diagram
from diagrams.gcp.analytics import BigQuery, Dataflow, PubSub
from diagrams.gcp.compute import AppEngine, Functions
from diagrams.gcp.database import BigTable
from diagrams.gcp.iot import IotCore
from diagrams.gcp.storage import GCS

with Diagram(show=True, filename="diagram", graph_attr={"ceter": "true"}):
    pubsub = PubSub("pubsub")
    iotcore = [IotCore("core1"), IotCore("core2"), IotCore("core3")]
    iotcore >> pubsub

    with Cluster("Targets"):
        with Cluster("Data Flow"):
            flow = Dataflow("data flow")
        with Cluster("Data Lake"):
            flow >> [BigQuery("bq"), GCS("storage")]
        with Cluster("Event Driven"):
            flow >> AppEngine("engine") >> BigTable("bigtable")
            flow >> Functions("func") >> AppEngine("appengine")

    pubsub >> flow
