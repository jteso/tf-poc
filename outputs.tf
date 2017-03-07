
output "ha-address" {
  value = "${aws_elb.2tier-apache-ha-elb.dns_name}"
}

output "address" {
  value = "${aws_elb.2tier-apache-elb.dns_name}"
}
