from web3 import Web3, HTTPProvider
import rlp
import math
import time
import json
from ethereum.transactions import Transaction


class Auction:
    CREATE_ADDRESS = "0xda7fab79bfd0a27f04367f5b9b9348cb5d1b0023"
    CREATE_PRI_KEY = ""
    Land_ADDRESS = "0x8df7287914144d89adf44d8fdd0b72f4990fb2fc"
    Genesis_HOLDER = "0x59ec5f5f80ff8ae02049eeeea149c2befa63772b"
    ETH_RPC = "https://kovan.infura.io/ZWef2NOidUm5XooBYqgl"
    ringTokenAddress = "0x6df4e0da83e47e3f6cd7d725224bc73f0e198c4f"
    FirstAuctionTime = '2018-10-1 22:00:00'

    def run(self):
        w3 = Web3(HTTPProvider(self.ETH_RPC, request_kwargs={'timeout': 120}))
        nonce = w3.eth.getTransactionCount(self.CREATE_ADDRESS),
        nonce = nonce[0]
        FirstAuctionTimeStamp = int(time.mktime(time.strptime(self.FirstAuctionTime, '%Y-%m-%d %H:%M:%S')))

        with open('resource.json', 'r') as resource_definition:
            resource_json = json.load(resource_definition)
        with open('land.abi', 'r') as land_definition:
            land_abi = json.load(land_definition)

        nonceAdd = 0
        ignoreCoord = self.ignore_coord()
        for index, land in enumerate(resource_json):
            x = -112 + index % 45
            y = 22 - int(index / 45)
            coord = str(x) + "," + str(y)
            if land["isSpecial"] == 1 or land["isSpecial"] == 2 or coord in ignoreCoord:  # Reserved land
                print(coord)
                continue
            land_contract = w3.eth.contract(address=self.Land_ADDRESS, abi=land_abi)
            try:
                landTokenId = land_contract.call().encodeTokenId(x, y)
            except:
                print("have error ", index, coord)
                break
            else:
                startingPriceInToken = Web3.toWei(6000, 'ether')
                endingPriceInToken = int(startingPriceInToken / 5)
                duration = 3600 * 6
                startAt = FirstAuctionTimeStamp + 3600 * index
                execute_transaction = "0x6e3630a8" + \
                                      self.u256ToInput(landTokenId) + \
                                      self.u256ToInput(startingPriceInToken) + \
                                      self.u256ToInput(endingPriceInToken) + \
                                      self.u256ToInput(duration) + \
                                      self.u256ToInput(startAt) + \
                                      self.pandding(self.ringTokenAddress)

                tx = Transaction(
                    nonce=nonce + nonceAdd,
                    gasprice=2000000000,
                    startgas=1000000,
                    to=self.Genesis_HOLDER,
                    value=0,
                    data=w3.toBytes(hexstr=execute_transaction),
                )
                tx.sign(self.CREATE_PRI_KEY)
                raw_tx = rlp.encode(tx)
                raw_tx_hex = w3.toHex(raw_tx)
                tx = w3.eth.sendRawTransaction(raw_tx_hex)
                nonceAdd += 1
                print(tx)

    def pandding(self, format):
        if format.startswith('0x'):
            format = format[2:]
        return format.rjust(64, '0')

    def panddingF(self, format):
        if format.startswith('0x'):
            format = format[2:]
        return format.rjust(64, 'f')

    def u256ToInput(self, u):
        if u >= 0:
            hex = "{:x}".format(u)
            return self.pandding(hex)
        else:
            if abs(u) == 1:
                hex = "{:x}".format(16 - abs(u))
            else:
                hex = "{:x}".format(int(pow(16, math.ceil(math.log(abs(u), 16))) + u))
            return self.panddingF(hex)

    def ignore_coord(self):
        file = open("resource-land-not-auction.txt", 'r+')
        coord = []
        while 1:
            c = file.readline().strip('\n')
            if not c:
                break
            coord.append(c)
        file.truncate()
        file.close()
        return coord

if __name__ == '__main__':
    ld = Auction()
    ld.run()
