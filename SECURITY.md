# Security policy

This project is a learning lab and a reference stack. It is not a hardened production platform; see the limits in the README.

## Reporting a problem

Please open a private security advisory on GitHub (Security tab, "Report a vulnerability") or an issue without exploit details. Include the version, what you did and what you saw. You will get an answer when the maintainer reads it; there is no support SLA.

## What is in scope

- Secrets or credentials committed by mistake
- Insecure defaults in the Terraform, Ansible or Kubernetes code
- Instructions that leave a system open without saying so

## What is out of scope

- Multi-tenant isolation guarantees: a single node gives only soft isolation
- Cost overruns caused by resources you forgot to destroy
