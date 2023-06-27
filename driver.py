import os
import sys
import mmap
import fcntl
import struct
import asyncio


class ZyboDriver:
    def __init__(self, op, device='/dev/uio/user_io'):
        self.fd = os.open(device, os.O_RDWR)
        fcntl.fcntl(self.fd, fcntl.F_SETFL, os.O_NONBLOCK)
        self.mm = mmap.mmap(self.fd, 0x1000)
        if op == 'read':
            asyncio.get_event_loop().add_reader(self.fd, self.__irq_handler)
            self.__irq_unmask()
        elif op == 'clear':
            self.mm[4:8] = b'\x01\x00\x00\x00'
        else:
            raise ValueError(f'unsupported operation {op}')

    def enviar(self, port, data):
        #print('send', port, data)
        for b in data:
            self.mm[port*4:port*4+4] = struct.pack('I', b)

    def __irq_handler(self):
        os.read(self.fd, 4)   # diz ao SO que coletamos a irq
        while True:
            elem, = struct.unpack('i', self.mm[0:4])  # retira da fila do hardware
            if elem == -1: break                      # fila vazia
            print(elem)
        self.__irq_unmask()

    def __irq_unmask(self):
        os.write(self.fd, b'\x01\x00\x00\x00')


if __name__ == '__main__':
    driver = ZyboDriver(sys.argv[1])
    asyncio.get_event_loop().run_forever()
