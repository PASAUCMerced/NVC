import glob
import errno
path = '/home/cc/nvc/tests/cmr*'
files = glob.glob(path)
resultfile = open("/home/cc/nvc/tests/result.txt","w+")
for name in files:
    try:
        with open(name) as f:
            line = f.readline()
            resultfile.write(line)
            resultfile.write("\n")
            f.close()
    except IOError as exc:
        print("error\n")
        if exc.errno != errno.EISDIR:
            raise

resultfile.close()
