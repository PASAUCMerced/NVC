import glob
import errno
path = '/home/cc/nvc/tests/result.out.*'
files = glob.glob(path)
count = 0
for name in files:
        count = count + 1

print(count)

