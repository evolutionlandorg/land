from web3 import Web3, HTTPProvider
import rlp
import json
from ethereum.transactions import Transaction
import math

class LandData:
    def run(self):
        # desc
        # -112 <= x <= -68
        # -22 <= y <= 22
        # --
        LandData_ADDRESS = "0xb8897c52641991086abb4985ce5adb7bce032ae8"
        Land_ADDRESS = "0x1a587212c0e35922ee79e4ff876c5e4e600fc877"
        ETH_RPC = "https://kovan.infura.io/ZWef2NOidUm5XooBYqgl"
        USER_ADDRESS = ""
        CREATE_PRI_KEY = ""

        w3 = Web3(HTTPProvider(ETH_RPC, request_kwargs={'timeout': 120}))
        with open('landData.abi', 'r') as landData_definition:
            landData_abi = json.load(landData_definition)
        with open('land.abi', 'r') as land_definition:
            land_abi = json.load(land_definition)
        with open('resource.json', 'r') as resource_definition:
            resource_json = json.load(resource_definition)

        nonce = w3.eth.getTransactionCount(USER_ADDRESS),
        nonce = nonce[0]
        for index, resource in enumerate(resource_json):
            x = -112 + index % 45
            y = 22 - int(index / 45)
            land_contract = w3.eth.contract(address=Land_ADDRESS, abi=land_abi)
            try:
                landTokenId = land_contract.call().encodeTokenId(x, y)
            except:
                break
            else:
                goldRate, woodRate, waterRate, fireRate, soilRate, isReserved = resource["gold"], resource["wood"], resource["water"], resource[
                    "fire"], resource["earth"], resource["isSpecial"]
                print(landTokenId, goldRate, woodRate, waterRate, fireRate, soilRate, isReserved)
                x = goldRate + (woodRate << 16) + (waterRate << 32) + (fireRate << 48) + (soilRate << 64) + (isReserved << 80)
                execute_transaction = "0x4d628d48" + self.u256ToInput(landTokenId) + self.u256ToInput(x)
                tx = Transaction(
                    nonce=nonce + index,
                    gasprice=2000000000,
                    startgas=1000000,
                    to=LandData_ADDRESS,
                    value=0,
                    data=w3.toBytes(hexstr=execute_transaction),
                )
                tx.sign(CREATE_PRI_KEY)
                raw_tx = rlp.encode(tx)
                raw_tx_hex = w3.toHex(raw_tx)
                tx = w3.eth.sendRawTransaction(raw_tx_hex)
                print(tx)
                break


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


if __name__ == '__main__':
    ld = LandData()
    ld.run()
