import sys
import numpy as np
import matplotlib.pyplot as plt

arr=np.loadtxt(sys.argv[1])

arr2=np.zeros(len(arr))
arr2[arr==1]=-1
arr2[arr==2]=1
arr2[arr==3]=0

plt.plot(arr2,'k')
plt.show()
