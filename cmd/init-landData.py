from web3 import Web3, HTTPProvider
import rlp
import json
from ethereum.transactions import Transaction


class LandData:
    def run(self):
        # desc
        # -112 <= x <= -68
        # -22 <= y <= 22
        # --
        LandData_Contract = "0xb58bd9f8bd20332d885b4887449b228b8082da42"
        Land_Contract = "0xcd0216736ab8514b1c0f7f2a6817c819c356fa0f"
        ETH_RPC = "https://kovan.infura.io/ZWef2NOidUm5XooBYqgl"
        USER_ADDRESS = ""
        CREATE_PRI_KEY = ""

        w3 = Web3(HTTPProvider(ETH_RPC, request_kwargs={'timeout': 120}))
        with open('landData.abi', 'r') as landData_definition:
            landData_abi = json.load(landData_definition)
        with open('land.abi', 'r') as land_definition:
            land_abi = json.load(land_definition)

        land_contract = w3.eth.contract(address=Land_Contract, abi=land_abi)
        landData_contract = w3.eth.contract(address=LandData_Contract, abi=landData_abi)
        nonce = w3.eth.getTransactionCount(USER_ADDRESS),
        nonce = nonce[0]
        count = 300
        for i in range(count):
            landIndex = i
            try:
                landTokenId = land_contract.call().tokenByIndex(landIndex)
            except:
                break
            else:
                cood = land_contract.call().decodeTokenId(landTokenId)
                x, y = cood[0], cood[1]
                encodeTokenId = landData_contract.call().encodeTokenId(x, y)
                goldRate, woodRate, waterRate, fireRate, soilRate = 1, 1, 1, 1, 1
                isReserved = 1
                isSpecial = 1
                hasBox = 1
                x = encodeTokenId + (goldRate << 48) + (woodRate << 64) + (waterRate << 80) + (fireRate << 96) + \
                    (soilRate << 112) + (isReserved << 128) + (isSpecial << 129) + (hasBox << 130)
                execute_transaction = "0x4d628d48" + self.u256ToInput(landTokenId) + self.u256ToInput(x)
                tx = Transaction(
                    nonce=nonce + i,
                    gasprice=6000000000,
                    startgas=1000000,
                    to=LandData_Contract,
                    value=0,
                    data=w3.toBytes(hexstr=execute_transaction),
                )
                tx.sign(CREATE_PRI_KEY)
                raw_tx = rlp.encode(tx)
                raw_tx_hex = w3.toHex(raw_tx)
                tx = w3.eth.sendRawTransaction(raw_tx_hex)
                print(tx)

    def pandding(self, format):
        if format.startswith('0x'):
            format = format[2:]
        return format.rjust(64, '0')

    def u256ToInput(self, u):
        hex = "{:x}".format(u)
        return self.pandding(hex)


if __name__ == '__main__':
    ld = LandData()
    ld.run()
