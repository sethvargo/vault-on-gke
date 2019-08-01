# Changelog

All notable changes to this project will be documented in this file.

## [0.2.0] - 2019-08-01
### Breaking
- These configurations now require Terraform 0.12+
- Deploy Vault 1.2.0 by default
- Some variable types have changed to be 0.12 compatible

### Added
- More documentation on securing Terraform state

### Changed
- Stop writing Vault TLS private key to disk
- Reduce required KMS key permissions now that hashicorp/vault#5999 has been out for awhile

## [0.1.2] - 2019-02-19
### Added
- Include CA cert in configmap

### Changed
- Choose google vs google-beta provider

## [0.1.1] - 2019-01-12

### Added
- New networking configuration options

### Changed
- Use private clusters


## [0.1.0] - 2019-01-07

### Added
- Preserve client IP addresses in audit logs
- Configurable number of recovery shares and threshold
- Listen on localhost in the container
- Reduce required KMS IAM permissions


## [0.0.1] - 2018-4-27

### Added
- Initial release
