# Outputs file
output "voting-app_url" {
  value = "http://${aws_eip.mpn.public_dns}:5000"
}

output "result-app_url" {
  value = "http://${aws_eip.mpn.public_dns}:5001"
}

output "prometheus_url" {
  value = "http://${aws_eip.mpn.public_dns}:9090"
}

output "grafana-app_url" {
  value = "http://${aws_eip.mpn.public_dns}:3000"
}