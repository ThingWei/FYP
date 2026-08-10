const { expect } = require('chai');
const { ethers } = require('hardhat');
describe('RentalAgreement', function () {
  async function fixture() {
    const [backend, renter, owner, outsider] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory('RentalAgreement');
    const agreement = await Factory.deploy(renter.address, owner.address, 100n, 50n, { value: 150n });
    return { agreement, backend, renter, owner, outsider };
  }
  it('activates only after both signatures', async function () { const { agreement, renter, owner } = await fixture(); await agreement.connect(renter).sign(); expect(await agreement.state()).to.equal(0); await agreement.connect(owner).sign(); expect(await agreement.state()).to.equal(1); });
  it('prevents outsider signing and non-backend completion', async function () { const { agreement, renter, owner, outsider } = await fixture(); await expect(agreement.connect(outsider).sign()).to.be.revertedWith('Party only'); await agreement.connect(renter).sign(); await agreement.connect(owner).sign(); await expect(agreement.connect(owner).complete(0)).to.be.revertedWith('Backend only'); });
  it('supports dispute and backend resolution', async function () { const { agreement, renter, owner } = await fixture(); await agreement.connect(renter).sign(); await agreement.connect(owner).sign(); await agreement.connect(renter).openDispute(); await agreement.resolve(75, 'DISPUTE-1'); expect(await agreement.state()).to.equal(5); });
});

