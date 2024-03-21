/*
// recomment this in when I can transfer the domain out of CF.
See  https://community.cloudflare.com/t/do-i-just-need-to-wait/629208
locals {
  regions_and_continents = flatten([
    for region in var.regions : [
      for continent in region.continents : {
        region = region.region
        continent = continent
      }
    ]
  ])
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
}


resource "aws_route53_record" "geo_routing" {
    // a record for each continent. Every continent requires its own route53_record
  count   = length(local.regions_and_continents)
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  set_identifier = "${local.regions_and_continents[count.index]["region"]}-${local.regions_and_continents[count.index]["continent"]}"

  geolocation_routing_policy {
    continent = local.regions_and_continents[count.index]["continent"]
  }

  ttl = "300"
  // simple routing policy, computed ahead of time. 
  // look at config.json->regions->continents for routing information
  records = [module.ec2.instance_public_ips[local.regions_and_continents[count.index]["region"]]]

}

resource "aws_route53_health_check" "health_check" {
  count = length(local.regions_and_continents)
  fqdn = "${local.regions_and_continents[count.index]["region"]}.${var.domain_name}"
  port = 80
  type = "HTTP"
  resource_path = "/"
  failure_threshold = "2"
  request_interval = "30"

  tags = {
    Name = "${local.regions_and_continents[count.index]["region"]}-${local.regions_and_continents[count.index]["continent"]}-health-check"
  }
}

resource "aws_route53_record" "health_check_routing" {
  count   = length(local.regions_and_continents)
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  set_identifier = "${local.regions_and_continents[count.index]["region"]}-${local.regions_and_continents[count.index]["continent"]}-health-check"

  health_check_id = aws_route53_health_check.health_check[count.index].id

  geolocation_routing_policy {
    continent = local.regions_and_continents[count.index]["continent"]
  }

  ttl = "300"
  records = [module.ec2.instance_public_ips[local.regions_and_continents[count.index]["region"]]]
}


output "name_servers" {
  description = "The DNS name servers for the domain"
  value       = aws_route53_zone.main.name_servers
}

*/