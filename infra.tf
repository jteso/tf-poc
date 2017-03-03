// Provider Setup
provider "aws" {
	region	   = "${var.region}"
}


// Setup your S3 Bucket
resource "aws_s3_bucket" "cdn_bucket" {
  bucket = "${var.bucket_name}"
  acl = "public-read"
  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[{
    "Sid":"PublicReadForGetBucketObjects",
      "Effect":"Allow",
      "Principal": "*",
      "Action":"s3:GetObject",
      "Resource":["arn:aws:s3:::${var.bucket_name}/*"
      ]
    }
  ]
}
POLICY
}

// Setup the CloudFront Distribution
resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  origin {
    custom_origin_config {
        http_port = 80,
        https_port = 443,
        origin_protocol_policy = "http-only",
        origin_ssl_protocols = ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"]
    }
    domain_name = "${aws_s3_bucket.cdn_bucket.id}.s3-website-${var.region}.amazonaws.com"
    origin_id   = "${aws_s3_bucket.cdn_bucket.id}"

  }

  enabled = true
  price_class = "${var.price_class}"
  default_cache_behavior {
    allowed_methods = [ "DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT" ]
    cached_methods = [ "GET", "HEAD" ]
    target_origin_id = "${aws_s3_bucket.cdn_bucket.id}"
    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }
  retain_on_delete = "${var.retain_on_delete}"
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_route53_zone" "primary" {
   name = "maniflexx.com"
}

//Add Root Route53 Records
resource "aws_route53_record" "main_record" {
  zone_id =  "${aws_route53_zone.primary.zone_id}"
  name = "${var.domain_name}"
  type = "A"

  alias {
    name = "${aws_cloudfront_distribution.cloudfront_distribution.domain_name}"
    zone_id = "${aws_cloudfront_distribution.cloudfront_distribution.hosted_zone_id}" 
    evaluate_target_health = false
  }
}