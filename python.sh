#!/bin/bash

# where ctypes.sh is installed; you will likely have to change this
LD_LIBRARY_PATH=$HOME/local/lib
. ~/code/ctypes.sh/ctypes.sh

s=$(cat<<EOF
def add(*args):
    return sum(int(arg) for arg in args)
EOF
)

cat<<EOF >python.c
#include <assert.h>

#include <Python.h>

// Marshal the input words. This will return a Python tuple object containing
// all of the strings passed in.
PyObject *MarshalParams(const char **words, size_t count) {
  PyObject *list = PyTuple_New(count);
  for (size_t i = 0; i < count; i++) {
    PyObject *s = PyString_FromString(words[i]);
    PyTuple_SET_ITEM(list, (Py_ssize_t)i, s);
  }
  return list;
}

// XXX: leaks references
PyObject *CreateFunction(const char *funcname, const char *code) {
  // compile a code object
  PyObject *compiled = Py_CompileString(code, "", Py_file_input);
  assert(compiled != NULL);

  // build a module w/ the code object
  PyObject *module = PyImport_ExecCodeModule((char *)funcname, compiled);
  assert(module != NULL);

  // get the function we created
  PyObject *method = PyObject_GetAttrString(module, (char *)funcname);
  assert(method != NULL);

  return method;
}
EOF

function build_python {
    sofile=$(mktemp /tmp/XXXXXX.so)
    cc $(pkg-config --cflags --libs python) -fPIC -shared python.c -o $sofile
    echo $sofile
}

sofile=$(build_python)

trap "rm -f $sofile python.c" EXIT

declare -i wordsize=8  # i.e. 64-bit
declare -i numwords=3
declare -a words
words=(string:1 string:2 string:3)

# allocate space for our packed words
dlcall -n buffer -r pointer malloc $((numwords * wordsize))
pack $buffer words

# load the code
dlopen $sofile

# initialize the python interpreter
dlcall Py_Initialize

# marshal the params
dlcall -n pytuple -r pointer MarshalParams $buffer long:$numwords
echo "pytuple is $pytuple"

# create a python function object for "add"
dlcall -n pyfunc -r pointer CreateFunction string:add string:"$s"
echo "pyfunc is $pyfunc"

dlcall -n out -r pointer PyObject_CallObject $pyfunc $pytuple
echo "out is $out"

dlcall -n res -r long PyInt_AsLong $out
echo "res is $res"
