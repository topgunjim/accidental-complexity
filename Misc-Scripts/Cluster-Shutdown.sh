# 1. Cordon all nodes
kubectl cordon $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

# 2. Drain workers
for node in $(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}'); do
  echo "Draining $node..."
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data --timeout=60s
done

# 3. Drain head node
kubectl drain headnode --ignore-daemonsets --delete-emptydir-data --timeout=60s

# 4. Shutdown workers
for ip in node01-ip node02-ip node03-ip .....
  echo "Shutting down $ip..."
  ssh pi@$ip "sudo shutdown -h now" 2>/dev/null || true
done

# 5. Shutdown head node last
sudo shutdown -h now
