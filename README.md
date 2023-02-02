# `tf`
A tool built on top of `terraform` to help make infrastructure management a bit easier.

## Installation
    # Install tfenv on macOS, then install the version of Terraform we are using in `hello-world`. e.g. `0.14.11` from (https://github.com/Hustle/hello-world/blob/master/infra/terraform/ecs-cluster/src/provider.tf#L8)
    brew install tfenv
    tfenv install 0.14.11

    # Install tf
    npm install -g Hustle/tf

    # Add an environment variable so `tf` can find infrastructure projects
    export TF_INFRA_DIR=/path/to/hello-world/infra/terraform/

If the environment variable `TF_INFRA_DIR` is not set, `tf` will use the current working directory.

We currently do not have a standardized provider configuration block used across all services. Because of this, you will need to switch between Terraform versions. `tfenv` is a package that allows us to manage multiple Terraform versions.

    # Install tfenv on macOS
    brew install tfenv

Terraform version `1.0.1` and earlier do not have ARM binaries. Rosetta will be needed to run these versions.

    # install Rosetta on macOS
    softwareupdate --install-rosetta

Create both the `default` and `infra` AWS profiles. Apply the same credentials to both.

    # Configure default profile
    aws configure

    # Configure infra profile
    aws configure --profile infra

## Usage
Install Terraform version declared in `./src/provider.tf` within the folder of the AWS service you are managing.

    # Install a specificied version of Terraform
    tfenv install <version>

    # Set default Terraform version
    tfenv set <version>

Terraform version `1.0.1` and earlier do not have ARM binaries. To install these versions use the following syntax.

    #Install non ARM Terraform binary
    TFENV_ARCH=amd64 tfenv install <version>

`tf` expects your working directory to be `${PATH_TO_hello-world_REPO}/infra/terraform`. Runing from any other location will result in an error.

    Usage: tf [options] <command> <project> <env> [terraformArgs...]

    Infrastructure management tool


    Options:

      -V, --version            output the version number
      -g, --group <group>      specify group for multiple projects in the same <env>
      -f, --force              force destroy without prompt
      -p, --profile <profile>  AWS profile, default is infra
      -h, --help               output usage information


    Arguments:

      <command>
        plan    - Test the project's infrastructure plan, format and evaluate changes
        apply   - Apply the project's infrastructure
        destroy - Remove the project's infrastructure
        import  - Import an existing resource
        rename  - Rename an infrastructure resource
        remove  - Remove an infrastructure resource

      <project>
        A project name that maps to an infrastructure project directory

         Example: kafka => ./kafka

      <env>
         An environment name that maps to an infrastructure config file specific to
         the given environment

         Example: dev => ./<project>/config/dev.tfvars


    Examples:

      Run a plan for Kafka infrastructure in the dev environment
       $ tf plan kafka dev

      Apply infrastructure for networking in the staging environment
       $ tf apply network staging

      Import an existing widget to the staging environment
       $ tf import network staging aws_widgets.widget <widgetId>

      Run a plan for the default ECS cluster in the staging environment
       $ tf plan ecs-cluster staging

      Apply infrastructure for ECS service domain-event-sp in the staging environment
       $ tf apply ecs-service staging -g domain-event-sp

## Terraform

"Terraform is a tool for building, changing, and versioning infrastructure safely and efficiently." --<cite><a href="https://www.terraform.io/intro/index.html" target="_blank">terraform.io</a></cite>

## Why Abstract Terraform?
The short answer is managing remote Terraform state can be tedious and error prone, but necessary, especially when working with a team. Terraform has a ton of features that are not usually needed day-to-day. This tool abstracts the details of handling Terraform state and focuses on the most used features while also providing a simple framework for creating terraform projects. It ensures infrastructure state is maintained across machines and makes it easier and safer for engineers to collaborate. This abstraction should cover most needs for planning, applying and removing infrastructure. For everything else use `terraform`, but be aware of any operation that modifies remote state.

## Creating an Infrastructure Project

First, let's look at the basic structure of a `tf` infrastructure project and then break down the components.

    ├── README.md
    ├── config
    │   ├── defaults.tfvars
    │   ├── dev.tfvars
    │   ├── production.tfvars
    │   └── staging.tfvars
    └── src
        ├── data-sources.tf
        ├── main.tf
        └── provider.tf

### `README`
Describes the purpose and contents of the infrastructure project.

### `config`
Contains configuration files in [tfvars format](https://www.terraform.io/intro/getting-started/variables.html#from-a-file) that define the infrastructure for the region and environment. A *defaults* or *common* tfvars file is required and should define reasonable defaults to be used across environments.

Environment specific variables must be defined in the appropriate environment tfvars file. The environment config file name maps to the &lt;env&gt; argument when `tf` is invoked. `tf` will also check for a file called `${env}-secrets.tfvars`, and load it if it exists. This allows you to store secrets using a tool like [git-crypt](https://github.com/AGWA/git-crypt) while keeping the rest of your configuration in plain text. The secrets file is not required.

A project may need to further differentiate by *group* when it is necessary to deploy multiple groups of the same infrastructure in the same environment. For example, multiple ECS services exist in an ECS cluster and therefore groups are needed to define their unique configuration. Group variables must exist in a directory with the same name as the environment. For example, an ECS service config directory structure may look like:

    ├── config
    │   ├── defaults.tfvars
    │   ├── production
    │   │   ├── mongo-state-sp.tfvars
    │   │   └── domain-event-sp.tfvars
    │   ├── production.tfvars
    │   ├── production-secrets.tfvars
    │   ├── staging
    │   │   ├── mongo-state-sp.tfvars
    │   │   ├── domain-event-sp.tfvars
    │   └── staging.tfvars
    │   └── staging-secrets.tfvars

Given this structure, a command to apply infrastructure might be:

    # apply ECS service infrastructure for the mongo state processor in staging
    tf apply ecs-service staging -g mongo-state-sp

Configuration variables precedence is in the order of least specific to most specific where the more specific configuration wins. For example, calling the command above would result in variables loading in this order:

    defaults.tfvars < staging.tfvars < staging/mongo-state-sp.tfvars

### `src`
The source directory contains files that describe the state of the infrastructure for a given provider in the [tf file format](https://www.terraform.io/docs/configuration/syntax.html).

The **provider.tf** defines the provider, AWS in the example below, along with the required terraform version and backend definition for remote state storage. In most cases this file can be copied as is from an existing infrastructure project.

    # Set cloud provider and region
    provider "aws" {
      region = "${var.aws_region}"
    }

    # Version requirement and backend partial for remote state management
    terraform {
      required_version = ">=0.11.1"

      backend "s3" {
        bucket  = "some-infrastructure-bucket"
        region  = "us-east-1"
        profile = "some-aws-profile"
      }
    }

The **data-sources.tf** defines any resources that need to be referenced but are built by other means, such as another infrastructure project or the AWS console. Data sources are only required when the resources are not defined in the current project and are needed to build new infrastructure. For example the AWS VPC resource is needed to create a new AWS security group resource, but likely defined in a **network** infrastructure project.

    data "aws_vpc" "main" {
      tags {
        Name = "${var.environment}-vpc"
      }
    }

    ...

    resource "aws_security_group" "cluster" {
      name        = "ECS cluster"
      description = "ECS cluster security group (${var.environment})"
      vpc_id      = "${data.aws_vpc.main.id}" # Using the data-source defined above

      tags {
        Name        = "${var.environment}-cluster-sg"
        environment = "${var.environment}"
      }
    }

Any files with the tf extension in the `src` directory will be included in the infrastructure. For most projects it is sufficient to have everything defined in a **main.tf**, however for larger projects it may make sense to organize similar resources into various files for readability.

## Development
1. Fork the [Hustle/tf](https://github.com/Hustle/tf) repository
1. Fix some bugs or add some new features
1. Submit a pull request 😎
