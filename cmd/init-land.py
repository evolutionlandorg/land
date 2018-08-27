from web3 import Web3, HTTPProvider
import rlp
import json
import math
from ethereum.transactions import Transaction


class Land:
    def run(self):
        # desc
        # -112 <= x <= -68
        # -22 <= y <= 22
        # --
        Land_ADDRESS = "0x1a587212c0e35922ee79e4ff876c5e4e600fc877"
        ETH_RPC = "https://kovan.infura.io/ZWef2NOidUm5XooBYqgl"
        USER_ADDRESS = "0xda7fab79bfd0a27f04367f5b9b9348cb5d1b0023"
        PANGU_ADDRESS = "0xda7fab79bfd0a27f04367f5b9b9348cb5d1b0023"

        CREATE_PRI_KEY = ""

        w3 = Web3(HTTPProvider(ETH_RPC, request_kwargs={'timeout': 120}))
        with open('resource.json', 'r') as resource_definition:
            resource_json = json.load(resource_definition)
        nonce = w3.eth.getTransactionCount(USER_ADDRESS),
        nonce = nonce[0]

        for index, resource in enumerate(resource_json):
            x = -112 + index % 45
            y = 22 - index % 45
            execute_transaction = "0x6bd50a14" + self.u256ToInput(x) + self.u256ToInput(y) + self.pandding(PANGU_ADDRESS)
            tx = Transaction(
                nonce=nonce + index,
                gasprice=2000000000,
                startgas=1000000,
                to=Land_ADDRESS,
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
            hex = "{:x}".format(int(pow(16, math.ceil(math.log(abs(u), 16))) + u))
            return self.panddingF(hex)


if __name__ == '__main__':
    ld = Land()
    ld.run()
