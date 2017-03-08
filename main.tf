
# Specify the provider and access details
provider "aws" {
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
    region = "${var.aws_region}"
}

resource "aws_key_pair" "2tier-apache" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "2tier-apache-vpc" {
  cidr_block = "192.168.1.0/24"
  tags {
        Project = "${var.project_name}"
    }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "2tier-apache-ig" {
  vpc_id = "${aws_vpc.2tier-apache-vpc.id}"
  tags {
        Project = "${var.project_name}"
    }
}

# Grant the VPC internet access on its main route table
resource "aws_route" "2tier-apache-internet-access-rt" {
  route_table_id         = "${aws_vpc.2tier-apache-vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.2tier-apache-ig.id}"
}

# Create first subnet to launch our instances into
resource "aws_subnet" "2tier-apache-192_168_1_0-sn" {
  vpc_id                  = "${aws_vpc.2tier-apache-vpc.id}"
  availability_zone       = "${var.aws_region}a"
  cidr_block              = "192.168.1.0/28"
  map_public_ip_on_launch = true
  tags {
        Project = "${var.project_name}"
    }
}

# Create second subnet to launch our instances into if HA requested
resource "aws_subnet" "2tier-apache-192_168_1_16-sn" {
  count                   = "${var.want_ha}"
  vpc_id                  = "${aws_vpc.2tier-apache-vpc.id}"
  availability_zone       = "${var.aws_region}b"
  cidr_block              = "192.168.1.16/28"
  map_public_ip_on_launch = true
  tags {
        Project = "${var.project_name}"
    }
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "2tier-apache-elb-sg" {
  name        = "2tier-apache-elb-sg"
  description = "Port 80 allow to elb"
  vpc_id      = "${aws_vpc.2tier-apache-vpc.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
        Project = "${var.project_name}"
    }
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "2tier-apache-sg" {
  name        = "2tier-apache-sg"
  description = "Port 22 and 80 allow to instances"
  vpc_id      = "${aws_vpc.2tier-apache-vpc.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Project = "${var.project_name}"
  }
}

# HA version of ELB if HA requested
resource "aws_elb" "2tier-apache-ha-elb" {
  name     = "${var.project_name}-2tier-apache-ha-elb"
  count           = "${var.want_ha}"
  subnets         = ["${aws_subnet.2tier-apache-192_168_1_0-sn.id}", "${aws_subnet.2tier-apache-192_168_1_16-sn.id}"]
  security_groups = ["${aws_security_group.2tier-apache-elb-sg.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  #access_logs {
   # bucket = "2tier-apache-logs"
  #  bucket_prefix = "2tier-apache"
  #  interval = 60
  #}
  tags {
        Project = "${var.project_name}"
    }
}


# Non HA version of ELB if HA not requested
resource "aws_elb" "2tier-apache-elb" {
  name     = "${var.project_name}-2tier-apache-elb"
  count           = "${1 - var.want_ha}"
  subnets         = ["${aws_subnet.2tier-apache-192_168_1_0-sn.id}"]
  security_groups = ["${aws_security_group.2tier-apache-elb-sg.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  #access_logs {
   # bucket = "2tier-apache-logs"
  #  bucket_prefix = "2tier-apache"
  #  interval = 60
  #}
  tag {
        Project = "${var.project_name}"
    }
}

resource "aws_launch_configuration" "2tier-apache-lc" {
    name_prefix = "${var.project_name}2tier-apache-lc-"
    image_id = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type = "t2.micro"
    associate_public_ip_address = "true"
    security_groups = ["${aws_security_group.2tier-apache-sg.id}"]
    key_name = "${var.key_name}"

    lifecycle {
      create_before_destroy = true
    }
}

# HA version of Autoscaling Group if HA requested
resource "aws_autoscaling_group" "2tier-apache-ha-ag" {
    name  = "2tier-apache-ha-ag"
    count = "${var.want_ha}"
    #availability_zones = ["${var.aws_az["0"]}","${var.aws_az["1"]}"]    
    availability_zones = ["${var.aws_region}a", "${var.aws_region}b"] 
    max_size             = 6
    min_size             = 2
    health_check_grace_period = 300
    health_check_type         = "EC2"
    desired_capacity          = 4
    launch_configuration = "${aws_launch_configuration.2tier-apache-lc.name}"
    vpc_zone_identifier = ["${aws_subnet.2tier-apache-192_168_1_0-sn.id}", "${aws_subnet.2tier-apache-192_168_1_16-sn.id}"]
    load_balancers = ["${aws_elb.2tier-apache-ha-elb.name}"]
    wait_for_elb_capacity = 3

    lifecycle {
      create_before_destroy = true
    }
  tag {
      key   = "Project"
      value = "${var.project_name}"
      propagate_at_launch = true
    }
}

#resource "aws_s3_bucket" "2tier-apache-logs" {
#    bucket = "2tier-apache-logs"
#    acl = "log-delivery-write"
#
#}

# Non HA version of Autoscaling Group if HA not requested
resource "aws_autoscaling_group" "2tier-apache-ag" {
  name  = "2tier-apache-ag"
  count = "${1 - var.want_ha}"
  #availability_zones = ["${var.aws_az["0"]}","${var.aws_az["1"]}"]
  availability_zones = ["${var.aws_region}a"]
  max_size             = 3
  min_size             = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 2
  launch_configuration = "${aws_launch_configuration.2tier-apache-lc.name}"
  vpc_zone_identifier = ["${aws_subnet.2tier-apache-192_168_1_0-sn.id}"]
  load_balancers = ["${aws_elb.2tier-apache-elb.name}"]
  wait_for_elb_capacity = 2

  lifecycle {
    create_before_destroy = true
  }
  tags {
        Project = "${var.project_name}"
  }
}

#resource "aws_s3_bucket" "2tier-apache-logs" {
#    bucket = "2tier-apache-logs"
#    acl = "log-delivery-write"
#
#}

# HA version of autoscaling policies & alarms if HA requested
resource "aws_autoscaling_policy" "2tier-apache-ha-ag-scale-up" {
  name  = "2tier-apache-ha-ag-scale-up"
  count = "${var.want_ha}"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.2tier-apache-ha-ag.name}"
}

resource "aws_autoscaling_policy" "2tier-apache-ha-ag-scale-down" {
  name  = "2tier-apache-ha-ag-scale-down"
  count = "${var.want_ha}"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.2tier-apache-ha-ag.name}"
}


resource "aws_cloudwatch_metric_alarm" "2tier-apache-ha-ag-cpu-high" {
  alarm_name = "2tier-apache-ha-ag-cpu-high"
  count      = "${var.want_ha}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "300"
  statistic = "Average"
  threshold = "50"
  alarm_description = "This metric monitors ec2 CPU for high utilization on 2tier-apache hosts"
  alarm_actions = [
      "${aws_autoscaling_policy.2tier-apache-ha-ag-scale-up.arn}"
  ]
  dimensions {
      AutoScalingGroupName = "${aws_autoscaling_group.2tier-apache-ha-ag.name}"
  }
}

resource "aws_cloudwatch_metric_alarm" "2tier-apache-ha-ag-cpu-low" {
  alarm_name = "2tier-apache-ha-ag-cpu-low"
  count      = "${var.want_ha}"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "300"
  statistic = "Average"
  threshold = "40"
  alarm_description = "This metric monitors ec2 cpu for low utilization on 2tier-apache hosts"
  alarm_actions = [
      "${aws_autoscaling_policy.2tier-apache-ha-ag-scale-down.arn}"
  ]
  dimensions {
      AutoScalingGroupName = "${aws_autoscaling_group.2tier-apache-ha-ag.name}"
  }
}




# Non HA version of autoscaling policies & alarms if HA notrequested
resource "aws_autoscaling_policy" "2tier-apache-ag-scale-up" {
  name  = "2tier-apache-ag-scale-up"
  count = "${1 - var.want_ha}"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.2tier-apache-ag.name}"
  tags {
      Project = "${var.project_name}"
  }
}

resource "aws_autoscaling_policy" "2tier-apache-ag-scale-down" {
  name  = "2tier-apache-ag-scale-down"
  count = "${1 - var.want_ha}"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.2tier-apache-ag.name}"
  tags {
      Project = "${var.project_name}"
  }
}


resource "aws_cloudwatch_metric_alarm" "2tier-apache-ag-cpu-high" {
  alarm_name = "2tier-apache-ag-cpu-high"
  count      = "${1 - var.want_ha}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "300"
  statistic = "Average"
  threshold = "50"
  alarm_description = "This metric monitors ec2 CPU for high utilization on 2tier-apache hosts"
  alarm_actions = [
      "${aws_autoscaling_policy.2tier-apache-ag-scale-up.arn}"
  ]
  dimensions {
      AutoScalingGroupName = "${aws_autoscaling_group.2tier-apache-ag.name}"
  }
  tags {
        Project = "${var.project_name}"
  }
}

resource "aws_cloudwatch_metric_alarm" "2tier-apache-ag-cpu-low" {
  alarm_name = "2tier-apache-ag-cpu-low"
  count      = "${1 - var.want_ha}"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "300"
  statistic = "Average"
  threshold = "40"
  alarm_description = "This metric monitors ec2 cpu for low utilization on 2tier-apache hosts"
  alarm_actions = [
      "${aws_autoscaling_policy.2tier-apache-ag-scale-down.arn}"
  ]
  dimensions {
      AutoScalingGroupName = "${aws_autoscaling_group.2tier-apache-ag.name}"
  }
  tags {
        Project = "${var.project_name}"
  }
}



  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  #provisioner "remote-exec" {
  #  inline = [
  #    "sudo apt-get -y update",
  #    "sudo apt-get -y install nginx",
  #    "sudo service nginx start",
  #  ]
  #}
