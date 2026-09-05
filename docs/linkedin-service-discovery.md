# LinkedIn post: ECS service discovery with Service Connect

---

🧩 How does one ECS service find another when task IPs change on every deployment?

Hardcoding an IP is not an option. So I built a small ECS lab in Terraform to answer it: one Fargate cluster running Streamlit -> FastAPI -> MongoDB, wired with ECS Service Connect.

## What I learned

🗺️ A namespace is a discovery boundary, not a placement boundary. Same cluster, same subnets, but a service only resolves names inside its own namespace.

🔌 Service Connect beats DNS discovery here. The client calls backend:8000 and an Envoy sidecar resolves it. No private hosted zone to pay for or clean up.

📦 One Terraform module per service pays for itself fast. Every service has the same shape - task definition, log group, security group, its own IAM roles - and differs only in image, port, sizing and who may call it. Adding a service is a 20 line file.

🔒 Discovery is not authorization. Security groups still do the real work, and the module turns that into one line: mongodb admits the backend's security group, backend admits the frontend's. Identity, not IP addresses.

💸 The sidecar is not free. 256 extra CPU units and 64 MiB minimum, out of the same task budget.

🙈 A client does not have to be discoverable. My frontend joins as a client only: it can resolve backend, but nothing can call it by name.

⚠️ And the gap I left open: all that work is inbound only. Egress is still 0.0.0.0/0, because image pulls and log delivery need a way out and there is no NAT. A compromised task can call anywhere it likes. The real fix is private subnets plus VPC endpoints for ECR, CloudWatch and SSM. That is the next experiment.

---

🔗 **Code**: https://github.com/nirgluzman/ecs-service-connect

📖 **AWS docs on Service Connect**: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html

---

#AWS #ECS #Terraform #DevOps #CloudArchitecture
