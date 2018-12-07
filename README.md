# LeaderElection

The Leader Election Kata

## Compilation

Clone the repo:

    git clone https://github.com/nicolafiorillo/leader_election.git

Get dependencies and compile:
  
    mix do deps.get, compile

Run tests:

    mix test

## Usage

To just verify the system behaviour, you can run some nodes, even in the same machine (use different listening port) with the following command:

    PORT=4001 ID=4001 iex -S mix

It creates a node with ID=4001 which listens to port 4001.
To create other nodes connecting to the previous one you have to indicate the active node to connect to:

    PORT=4002 ID=4002 FIRST_NODE=127.0.0.1:4001 iex -S mix

Connect other nodes to the first one:

    PORT=4003 ID=4003 FIRST_NODE=127.0.0.1:4001 iex -S mix
    PORT=4004 ID=4004 FIRST_NODE=127.0.0.1:4001 iex -S mix

The scripts node1.sh, node2.sh, node3.sh, and node4.sh (in the root folder) run nodes with port from 4001 to 4004, with id respectively from 4001 to 4004.
**Run each of them in different console sessions**: you can see that, as per requirements, the leader is the node with bigger ID in the connected node set.
