import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Contract, ContractFactory, JsonRpcProvider } from 'ethers';
import { env } from '../config/env.js';

const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../..',
);
const stateNames = ['created', 'active', 'completed', 'cancelled', 'disputed', 'resolved'];
let runtimePromise;

const disabled = (action = 'none') => ({
  mode: env.blockchainMode,
  status: 'unavailable',
  localPrototype: true,
  network: 'ganache-local',
  action,
  error: 'Blockchain integration is disabled',
  updatedAt: new Date(),
});

const units = (myr) => BigInt(Math.max(0, Math.round(Number(myr ?? 0) * 100)));

async function artifact() {
  const configured = env.rentalContractArtifact;
  const target = path.isAbsolute(configured)
    ? configured
    : path.resolve(repositoryRoot, configured.replace(/^\.\.\/\.\.\//, ''));
  return JSON.parse(await readFile(target, 'utf8'));
}

async function runtime() {
  if (env.blockchainMode !== 'ganache') return null;
  runtimePromise ??= (async () => {
    const provider = new JsonRpcProvider(env.ganacheRpcUrl);
    const [backend, renter, owner] = await Promise.all([
      provider.getSigner(0),
      provider.getSigner(1),
      provider.getSigner(2),
    ]);
    return { provider, backend, renter, owner };
  })();
  return runtimePromise;
}

async function execute(action, operation) {
  if (env.blockchainMode !== 'ganache') return disabled(action);
  try {
    const result = await operation(await runtime());
    return {
      mode: 'ganache', status: 'confirmed', localPrototype: true,
      network: 'ganache-local', action, updatedAt: new Date(), ...result,
    };
  } catch (error) {
    runtimePromise = undefined;
    return {
      mode: 'ganache', status: 'failed', localPrototype: true,
      network: 'ganache-local', action, error: error.shortMessage ?? error.message,
      updatedAt: new Date(),
    };
  }
}

async function connectedContract(runtimeValue, address, signer) {
  const definition = await artifact();
  return new Contract(address, definition.abi, signer ?? runtimeValue.backend);
}

async function confirmedTransaction(transaction) {
  const receipt = await transaction.wait();
  return receipt.hash;
}

export const blockchainAdapter = {
  async health() {
    if (env.blockchainMode !== 'ganache') {
      return {
        mode: env.blockchainMode,
        status: 'disabled',
        network: 'ganache-local',
      };
    }
    try {
      const chain = await runtime();
      const [network, blockNumber, definition] = await Promise.all([
        chain.provider.getNetwork(),
        chain.provider.getBlockNumber(),
        artifact(),
      ]);
      return {
        mode: 'ganache',
        status: 'up',
        network: 'ganache-local',
        chainId: network.chainId.toString(),
        blockNumber,
        contractArtifact: Boolean(definition.abi && definition.bytecode),
      };
    } catch (error) {
      runtimePromise = undefined;
      return {
        mode: 'ganache',
        status: 'down',
        network: 'ganache-local',
        error: error.shortMessage ?? error.message,
      };
    }
  },

  async createAgreement({ rentalAmount, depositAmount }) {
    return execute('create_and_sign', async (chain) => {
      const definition = await artifact();
      const renterAddress = await chain.renter.getAddress();
      const ownerAddress = await chain.owner.getAddress();
      const rental = units(rentalAmount);
      const deposit = units(depositAmount);
      const contract = await new ContractFactory(
        definition.abi,
        definition.bytecode,
        chain.backend,
      ).deploy(renterAddress, ownerAddress, rental, deposit, {
        value: rental + deposit,
      });
      const deployment = await contract.deploymentTransaction().wait();
      const contractAddress = await contract.getAddress();
      const renterSignature = await confirmedTransaction(
        await contract.connect(chain.renter).sign(),
      );
      const ownerSignature = await confirmedTransaction(
        await contract.connect(chain.owner).sign(),
      );
      return {
        contractAddress,
        deploymentTransactionHash: deployment.hash,
        lastTransactionHash: ownerSignature,
        signatureTransactionHashes: [renterSignature, ownerSignature],
        contractState: stateNames[Number(await contract.state())],
        unitPolicy: 'MYR cents represented as local test-chain wei',
      };
    });
  },

  async complete(address, depositDeduction) {
    return execute('complete', async (chain) => {
      const contract = await connectedContract(chain, address);
      const hash = await confirmedTransaction(await contract.complete(units(depositDeduction)));
      return { contractAddress: address, lastTransactionHash: hash, contractState: 'completed' };
    });
  },

  async cancel(address, ownerShare = 0) {
    return execute('cancel', async (chain) => {
      const contract = await connectedContract(chain, address);
      const hash = await confirmedTransaction(await contract.cancel(units(ownerShare)));
      return { contractAddress: address, lastTransactionHash: hash, contractState: 'cancelled' };
    });
  },

  async openDispute(address, role) {
    return execute('open_dispute', async (chain) => {
      const signer = role === 'owner' ? chain.owner : chain.renter;
      const contract = await connectedContract(chain, address, signer);
      const hash = await confirmedTransaction(await contract.openDispute());
      return { contractAddress: address, lastTransactionHash: hash, contractState: 'disputed' };
    });
  },

  async resolve(address, renterAmount, reference) {
    return execute('resolve', async (chain) => {
      const contract = await connectedContract(chain, address);
      const balance = await chain.provider.getBalance(address);
      const renterShare = units(renterAmount) > balance ? balance : units(renterAmount);
      const hash = await confirmedTransaction(await contract.resolve(renterShare, reference));
      return { contractAddress: address, lastTransactionHash: hash, contractState: 'resolved' };
    });
  },

  async dismissDispute(address) {
    return execute('dismiss_dispute', async (chain) => {
      const contract = await connectedContract(chain, address);
      const hash = await confirmedTransaction(await contract.dismissDispute());
      return { contractAddress: address, lastTransactionHash: hash, contractState: 'active' };
    });
  },
};

