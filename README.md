# OpenZeppelin Contracts

This repository is used to verify the contract on the browser

## Usage

```
Usage: hardhat [GLOBAL OPTIONS] verify [--constructor-args <INPUTFILE>] [--contract <STRING>] [--libraries <INPUTFILE>] [--list-networks] [address] [...constructorArgsParams]

OPTIONS:

  --constructor-args    File path to a javascript module that exports the list of arguments.
  --contract            Fully qualified name of the contract to verify. Skips automatic detection of the contract. Use if the deployed bytecode matches more than one contract in your project.
  --libraries           File path to a javascript module that exports the dictionary of library addresses for your contract. Use if there are undetectable library addresses in your contract. Library addresses are undetectable if they are only used in the constructor for your contract.
  --list-networks       Print the list of supported networks

POSITIONAL ARGUMENTS:

  address               Address of the smart contract to verify
  constructorArgsParams Contract constructor arguments. Ignored if the --constructor-args option is used. (default: [])

verify: Verifies contract on Ethereum and zkSync networks

For global options help run: hardhat help
```
