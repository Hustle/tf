#!/usr/bin/env node

const fs = require('fs');
const cli = require('commander');
const pkg = require('./package.json');
const path = require('path');
const colors = require('colors');
const cmdExists = require('command-exists');
const { spawn, exec } = require('child_process');

// Bootstrapped terraform commands
const COMMANDS = [
  'plan',
  'apply',
  'import',
  'destroy',
  'rename',
  'remove',
];

const COMMAND_MAP = {
  rename: 'state mv',
  remove: 'state rm',
};

/** Functions **/

function exitWithError(msg, more) {
  console.error(msg.red);
  if (more) {
    console.error(`\n${more}`.bold.white);
  }
  process.exit(1);
}

function done(msg) {
  msg = msg || 'Done.';
  console.log(msg.green);
  process.exit(0);
}

function getConfigFileName(args) {
  if (fs.existsSync(`${args.cwd}/${args.project}/config/defaults.tfvars`)) {
    return 'defaults'
  }
  if (fs.existsSync(`${args.cwd}/${args.project}/config/common.tfvars`)) {
    return 'common';
  }
  return null;
}

function processCommand(cmd) {
  if (!COMMANDS.includes(cmd)) {
    exitWithError(
      `Invalid command, expected one of: ${COMMANDS.map(s => `'${s}'`).join(' | ')}`
    );
  }
}

function processProjectAndEnv(args, opts) {
  // check project directory
  if (!fs.existsSync(`${args.cwd}/${args.project}`)) {
    return exitWithError(
      `Invalid project '${args.project}'. Check available projects at ${args.cwd}`
    );
  }
  // check project src directory
  if (!fs.existsSync(`${args.cwd}/${args.project}/src`)) {
    exitWithError(
      `Missing required 'src' directory at ${args.cwd}/${args.project}/src`,
      'Check the ops/infrastructure README for help'
    );
  }
  // check project config directory
  if (!fs.existsSync(`${args.cwd}/${args.project}/config`)) {
    return exitWithError(
      `Missing required directory 'config' at ${args.cwd}/${args.project}/config`,
      'Check the ops/infrastructure README for help'
    );
  }
  // check environment config directory
  if (!fs.existsSync(`${args.cwd}/${args.project}/config/${args.env}.tfvars`)) {
    return exitWithError(
      `Missing required environment configuration at ${args.cwd}/${args.project}/config/${args.env}.tfvars`,
      'Check the ops/infrastructure README for help'
    );
  }
  if (opts.group && !fs.existsSync(`${args.cwd}/${args.project}/config/${args.env}/${opts.group}.tfvars`)) {
    return exitWithError(
      `Missing required environment group configuration at ${args.cwd}/${args.project}/config/${args.env}/${opts.group}.tfvars`,
      'Check the ops/infrastructure README for help'
    );
  }
  if (!getConfigFileName(args)) {
    return exitWithError(
      `Missing required config file 'common' or 'defaults' in the project config directory`,
      'Check the ops/infrastructure README for help'
    );
  }
  // check provider (aws and remote state store)
  if (!fs.existsSync(`${args.cwd}/${args.project}/src/provider.tf`)) {
    return exitWithError(
      `Project '${args.project}' is missing a backend configuration`,
      'Check the ops/infrastructure README for help'
    );
  }
}

function run(args, terraformArgs, opts) {
  // If we wrapped a command that is actually a subcommand of terraform then substitute
  if (args.command in COMMAND_MAP) {
    args.command = COMMAND_MAP[args.command];
  }

  cmdExists('terraform').then(() => {
    // Initialize state
    initState(args, opts).then(() => {
      // Run terraform command
      runCommand(args, terraformArgs, opts).then(done).catch(exitWithError);
    }).catch(exitWithError);
  }).catch(() => exitWithError('Please install `terraform` before running `tf`'));
}

function initState(args, opts) {
  const stateLocation = opts.group ? `${args.project}/${opts.group}` : args.project;
  const command = [
    'rm -rf ./.terraform',
    'rm -rf ./terraform.tfstate.backup',
    `terraform init -backend-config="key=terraform/${args.env}/${stateLocation}.tfstate"`
  ].join('; ');

  return new Promise((success, fail) => {
    console.log(`Initializing state for ${args.project} ${args.env} ${opts.group ? opts.group + ' ' : ''}...`);
    exec(command, { cwd: `${args.cwd}/${args.project}/src` }, (err, stdout, stderr) => {
      if (err || stderr) {
        const errMsg = err ? err.message : stderr;
        return fail(`An error occurred initializing state: ${errMsg}`);
      }
      console.log('State initialization complete.\n'.green);
      success();
    });
  });
}

function runCommand(args, terraformArgs, opts) {
  // Setup terraform command and options
  const runArgs = [
    ...args.command.split(' '),
    '-input=false',
    `-var 'environment=${args.env}'`
  ];

  // add config var file
  runArgs.push(`-var-file=../config/${getConfigFileName(args)}.tfvars`);

  // add env var file
  runArgs.push(`-var-file=../config/${args.env}.tfvars`);

  // add group var file
  if (opts.group) {
    runArgs.push(`-var-file=../config/${args.env}/${opts.group}.tfvars`)
  }

  // skip prompts on force
  if (opts.force && ['destroy', 'apply'].includes(args.command)) {
    runArgs.push(args.command === 'apply' ? '-auto-approve' : '-force');
  }

  // add terraform args (passed to wrapped terraform)
  runArgs.push(...terraformArgs);

  return new Promise((success, fail) => {
    const runner = (err, stdout, stderr) => {
      if (err || stderr) {
        const errMsg = err ? err.message : stderr;
        return fail(`An error occurred while formatting: ${errMsg}`);
      }
      if (args.command === 'plan') {
        console.log('Formatting complete.\n'.green);
      }
      console.log(`Running ${args.command} for ${args.project} ${args.env} ${opts.group ? opts.group + ' ' : ''}...`);
      const child = spawn(`terraform`, runArgs, {
        cwd: `${args.cwd}/${args.project}/src`,
        stdio: [process.stdin, 'pipe', 'pipe'],
        shell: true,
        env: Object.assign({}, process.env, {
          AWS_PROFILE: opts.profile || 'infra'
        })
      });
      child.on('error', err => fail(`An error occurred running ${args.command}: ${err.message}`));
      child.stderr.on('data', d => console.error(d.toString()));
      child.stdout.on('data', d => console.log(d.toString()));
      child.on('close', () => success());
    };
    if (args.command === 'plan') {
      console.log(`Formatting ${args.project} ${args.env} ${opts.group ? opts.group + ' ' : ''}...`);
      exec('terraform fmt', { cwd: `${args.cwd}/${args.project}/src` }, runner);
    } else {
      runner();
    }
  });
}

/** CLI Handling **/

cli
  .version(pkg.version)
  .description(pkg.description)
  .arguments('<command> <project> <env> [terraformArgs...]')
  .option('-g, --group <group>', 'specify group for multiple projects in the same <env>')
  .option('-f, --force', 'force destroy without prompt')
  .option('-p, --profile <profile>', `AWS profile, default is ${'infra'.grey}`)
  .action((command, project, env, terraformArgs, opts) => {
    // setup args
    const args = {
      command,
      project,
      env,
      cwd: process.env.TF_INFRA_DIR || process.cwd()
    };

    // process input and run
    processCommand(command);
    processProjectAndEnv(args, opts);
    run(args, terraformArgs, opts);
  });

// Make help more helpful
cli.on('--help', () => {
  console.log(`

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
    ${' $ tf plan kafka dev '.bold}

    Apply infrastructure for networking in the staging environment
    ${' $ tf apply network staging '.bold}

    Import an existing widget to the staging environment
    ${' $ tf import network staging aws_widgets.widget <widgetId>'.bold}

    Run a plan for the default ECS cluster in the staging environment
    ${' $ tf plan ecs-cluster staging'.bold}

    Apply infrastructure for ECS service domain-event-sp in the staging environment
    ${' $ tf apply ecs-service staging -g domain-event-sp'.bold}
  `);
});

// Parse cli input
cli.parse(process.argv);

// print help when no args are passed
if (cli.args.length < 1) {
  console.log(cli.help());
  process.exit(0);
}
