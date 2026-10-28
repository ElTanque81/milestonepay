const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const POT = (n) => ethers.parseEther(String(n));
const REVIEW = 3600; // 1 hour

describe("MilestonePay", function () {
  let mp, client, freelancer, arbiter, stranger;

  async function create({ amounts = [POT(1), POT(2)], withArbiter = true } = {}) {
    const total = amounts.reduce((a, b) => a + b, 0n);
    await mp
      .connect(client)
      .createProject(
        freelancer.address,
        withArbiter ? arbiter.address : ethers.ZeroAddress,
        amounts,
        REVIEW,
        "Landing page",
        { value: total }
      );
    return await mp.projectCount();
  }

  beforeEach(async () => {
    [client, freelancer, arbiter, stranger] = await ethers.getSigners();
    mp = await ethers.deployContract("MilestonePay");
  });

  describe("createProject", () => {
    it("locks POT and stores milestones", async () => {
      const id = await create();
      const p = await mp.getProject(id);
      expect(p.client).to.equal(client.address);
      expect(p.totalAmount).to.equal(POT(3));
      expect((await mp.getMilestones(id)).length).to.equal(2);
      expect(await ethers.provider.getBalance(await mp.getAddress())).to.equal(POT(3));
      expect(await mp.getProjectsOf(freelancer.address)).to.deep.equal([id]);
    });

    it("rejects wrong msg.value", async () => {
      await expect(
        mp.connect(client).createProject(freelancer.address, arbiter.address, [POT(1)], REVIEW, "x", { value: POT(2) })
      ).to.be.revertedWithCustomError(mp, "WrongValue");
    });

    it("rejects invalid params", async () => {
      await expect(
        mp.connect(client).createProject(client.address, arbiter.address, [POT(1)], REVIEW, "x", { value: POT(1) })
      ).to.be.revertedWithCustomError(mp, "InvalidParams");
      await expect(
        mp.connect(client).createProject(freelancer.address, arbiter.address, [], REVIEW, "x", { value: 0 })
      ).to.be.revertedWithCustomError(mp, "InvalidParams");
      await expect(
        mp.connect(client).createProject(freelancer.address, arbiter.address, [0], REVIEW, "x", { value: 0 })
      ).to.be.revertedWithCustomError(mp, "InvalidParams");
      await expect(
        mp.connect(client).createProject(freelancer.address, arbiter.address, [POT(1)], 10, "x", { value: POT(1) })
      ).to.be.revertedWithCustomError(mp, "InvalidParams");
    });
  });

  describe("happy path", () => {
    it("accept → submit → approve pays the freelancer", async () => {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      await mp.connect(freelancer).submitMilestone(id, 0, "https://github.com/demo/pr/1");

      await expect(mp.connect(client).approveMilestone(id, 0)).to.changeEtherBalances(
        [freelancer, mp],
        [POT(1), -POT(1)]
      );
      const ms = await mp.getMilestones(id);
      expect(ms[0].status).to.equal(3); // Released
      expect(ms[0].proof).to.equal("https://github.com/demo/pr/1");
      expect(await mp.lockedAmount(id)).to.equal(POT(2));
    });

    it("closes the project when all milestones are settled", async () => {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      for (const i of [0, 1]) {
        await mp.connect(freelancer).submitMilestone(id, i, "done");
        await mp.connect(client).approveMilestone(id, i);
      }
      expect((await mp.getProject(id)).closed).to.equal(true);
      expect(await ethers.provider.getBalance(await mp.getAddress())).to.equal(0n);
    });
  });

  describe("access control", () => {
    it("only freelancer can accept and submit", async () => {
      const id = await create();
      await expect(mp.connect(stranger).acceptProject(id)).to.be.revertedWithCustomError(mp, "NotAuthorized");
      await mp.connect(freelancer).acceptProject(id);
      await expect(mp.connect(client).submitMilestone(id, 0, "x")).to.be.revertedWithCustomError(mp, "NotAuthorized");
    });

    it("cannot submit before accepting", async () => {
      const id = await create();
      await expect(mp.connect(freelancer).submitMilestone(id, 0, "x")).to.be.revertedWithCustomError(mp, "WrongStatus");
    });

    it("only client can approve", async () => {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      await mp.connect(freelancer).submitMilestone(id, 0, "x");
      await expect(mp.connect(freelancer).approveMilestone(id, 0)).to.be.revertedWithCustomError(mp, "NotAuthorized");
    });

    it("cannot approve twice", async () => {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      await mp.connect(freelancer).submitMilestone(id, 0, "x");
      await mp.connect(client).approveMilestone(id, 0);
      await expect(mp.connect(client).approveMilestone(id, 0)).to.be.revertedWithCustomError(mp, "WrongStatus");
    });
  });

  describe("cancel & withdraw", () => {
    it("client can cancel before acceptance with full refund", async () => {
      const id = await create();
      await expect(mp.connect(client).cancelProject(id)).to.changeEtherBalance(client, POT(3));
      expect((await mp.getProject(id)).closed).to.equal(true);
    });

    it("client cannot cancel after acceptance", async () => {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      await expect(mp.connect(client).cancelProject(id)).to.be.revertedWithCustomError(mp, "WrongStatus");
    });

    it("freelancer withdrawal refunds only pending milestones", async () => {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      await mp.connect(freelancer).submitMilestone(id, 0, "x");
      await expect(mp.connect(freelancer).withdrawFromProject(id)).to.changeEtherBalance(client, POT(2));
      // submitted milestone still claimable
      await expect(mp.connect(client).approveMilestone(id, 0)).to.changeEtherBalance(freelancer, POT(1));
      expect((await mp.getProject(id)).closed).to.equal(true);
    });
  });

  describe("timeout", () => {
    it("freelancer can claim after the review period", async () => {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      await mp.connect(freelancer).submitMilestone(id, 0, "x");
      await expect(mp.connect(freelancer).claimAfterTimeout(id, 0)).to.be.revertedWithCustomError(
        mp,
        "ReviewPeriodRunning"
      );
      await time.increase(REVIEW);
      await expect(mp.connect(freelancer).claimAfterTimeout(id, 0)).to.changeEtherBalance(freelancer, POT(1));
    });
  });

  describe("disputes", () => {
    async function disputed() {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      await mp.connect(freelancer).submitMilestone(id, 0, "x");
      await mp.connect(client).disputeMilestone(id, 0);
      return id;
    }

    it("dispute blocks the timeout claim", async () => {
      const id = await disputed();
      await time.increase(REVIEW);
      await expect(mp.connect(freelancer).claimAfterTimeout(id, 0)).to.be.revertedWithCustomError(mp, "WrongStatus");
    });

    it("cannot dispute after the review period", async () => {
      const id = await create();
      await mp.connect(freelancer).acceptProject(id);
      await mp.connect(freelancer).submitMilestone(id, 0, "x");
      await time.increase(REVIEW);
      await expect(mp.connect(client).disputeMilestone(id, 0)).to.be.revertedWithCustomError(mp, "WrongStatus");
    });

    it("arbiter can pay the freelancer", async () => {
      const id = await disputed();
      await expect(mp.connect(arbiter).resolveDispute(id, 0, true)).to.changeEtherBalance(freelancer, POT(1));
    });

    it("arbiter can refund the client", async () => {
      const id = await disputed();
      await expect(mp.connect(arbiter).resolveDispute(id, 0, false)).to.changeEtherBalance(client, POT(1));
      expect((await mp.getMilestones(id))[0].status).to.equal(4); // Refunded
    });

    it("only arbiter can resolve", async () => {
      const id = await disputed();
      await expect(mp.connect(client).resolveDispute(id, 0, false)).to.be.revertedWithCustomError(mp, "NotAuthorized");
    });

    it("disputes need an arbiter", async () => {
      const id = await create({ withArbiter: false });
      await mp.connect(freelancer).acceptProject(id);
      await mp.connect(freelancer).submitMilestone(id, 0, "x");
      await expect(mp.connect(client).disputeMilestone(id, 0)).to.be.revertedWithCustomError(mp, "NoArbiter");
    });
  });
});
