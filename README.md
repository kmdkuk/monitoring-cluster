# vm-cluster

- grafana-operator
- loki
- victoriametrics
- promtail

setup

```console
$ make setup-tools
$ make start
$ make create-minio
$ kustomize build . | kubectl apply -f -
```

```
$ make grafana-port-forward
make get-grafana-password
make[1]: Entering directory '/home/vagrant/go/src/github.com/kmdkuk/vm-cluster'
/home/vagrant/go/src/github.com/kmdkuk/vm-cluster/bin/kubectl  get secret -n monitoring grafana-admin-credentials -o jsonpath="{.data.GF_SECURITY_ADMIN_PASSWORD}" | base64 -d; echo
<passwrodが表示される>
make[1]: Leaving directory '/home/vagrant/go/src/github.com/kmdkuk/vm-cluster'
/home/vagrant/go/src/github.com/kmdkuk/vm-cluster/bin/kubectl port-forward -n monitoring svc/grafana-service 3000:3000
Forwarding from 127.0.0.1:3000 -> 3000
Forwarding from [::1]:3000 -> 3000
```

あとはlocalhost:3000にアクセスしてuserid=adminとして表示されてるパスワードを使ってログインすればよろし。
