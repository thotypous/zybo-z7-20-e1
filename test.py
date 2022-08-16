import os
import mmap
import fcntl
import struct
import asyncio
from collections import defaultdict


class ZyboDriver:
    def __init__(self, device='/dev/uio/user_io'):
        self.fd = os.open(device, os.O_RDWR)
        fcntl.fcntl(self.fd, fcntl.F_SETFL, os.O_NONBLOCK)
        self.mm = mmap.mmap(self.fd, 0x1000)
        asyncio.get_event_loop().add_reader(self.fd, self.__irq_handler)
        self.__irq_unmask()

    def obter_porta(self, port):
        """ Obtém uma porta para controlar a partir do software em Python """
        return ZyboSerialPort(self, port)

    def expor_porta_ao_linux(self, port):
        """ Conecta uma porta a uma PTY para expô-la ao Linux """
        pty = PTY()
        pty.registrar_recebedor(lambda dados: self.enviar(port, dados))
        self.registrar_recebedor(port, pty.enviar)
        return pty

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
    driver = ZyboDriver()
    asyncio.get_event_loop().run_forever()
