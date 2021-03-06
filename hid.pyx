import sys
from chid cimport *
from libc.stddef cimport wchar_t, size_t
from libc.string cimport memcpy, memset
from cpython.unicode cimport PyUnicode_FromUnicode

cdef extern from "ctype.h":
    int wcslen(wchar_t*)

cdef extern from "stdlib.h":
    void free(void* ptr)
    void* malloc(size_t size)

cdef extern from *:
    object PyUnicode_FromWideChar(const wchar_t *w, Py_ssize_t size)
    Py_ssize_t PyUnicode_AsWideChar(object unicode, wchar_t *w, Py_ssize_t size)

cdef object U(wchar_t *wcs):
    if wcs == NULL:
        return ''
    cdef int n = wcslen(wcs)
    return PyUnicode_FromWideChar(wcs, n)

def enumerate(int vendor_id=0, int product_id=0):
    cdef hid_device_info* info = hid_enumerate(vendor_id, product_id)
    cdef hid_device_info* c = info
    res = []
    while c:
        res.append({
            'path': c.path,
            'vendor_id': c.vendor_id,
            'product_id': c.product_id,
            'serial_number': U(c.serial_number),
            'release_number': c.release_number,
            'manufacturer_string': U(c.manufacturer_string),
            'product_string': U(c.product_string),
            'usage_page': c.usage_page,
            'usage': c.usage,
            'interface_number': c.interface_number,
        })
        c = c.next
    hid_free_enumeration(info)
    return res

cdef class device:
    cdef hid_device *_c_hid

    def open(self, int vendor_id=0, int product_id=0, unicode serial_number=None):
        cdef wchar_t * cserial_number = NULL
        cdef int serial_len
        cdef Py_ssize_t result
        try:
            if serial_number is not None:
                serial_len = len(serial_number)
                cserial_number = <wchar_t*>malloc(sizeof(wchar_t) * (serial_len+1))
                if cserial_number == NULL:
                    raise MemoryError()
                result = PyUnicode_AsWideChar(serial_number, cserial_number, serial_len)
                if result == -1:
                    raise ValueError("invalid serial number string")
                cserial_number[serial_len] = 0  # Must explicitly null-terminate
            self._c_hid = hid_open(vendor_id, product_id, cserial_number)
        finally:
            if cserial_number != NULL:
                free(cserial_number)
        if self._c_hid == NULL:
            raise IOError('open failed')

    def open_path(self, bytes path):
        cdef char* cbuff = path
        self._c_hid = hid_open_path(cbuff)
        if self._c_hid == NULL:
            raise IOError('open failed')

    def close(self):
        if self._c_hid != NULL:
            hid_close(self._c_hid)
            self._c_hid = NULL

    def write(self, buff):
        '''Accept a list of integers (0-255) and send them to the device'''
        if self._c_hid == NULL:
            raise ValueError('not open')
        # convert to bytes
        if sys.version_info < (3, 0):
            buff = ''.join(map(chr, buff))
        else:
            buff = bytes(buff)
        cdef hid_device * c_hid = self._c_hid
        cdef unsigned char* cbuff = buff        # convert to c string
        cdef size_t c_buff_len = len(buff)
        cdef int res
        with nogil:
            res = hid_write(c_hid, cbuff, c_buff_len)
        
        if res < 0:
            raise IOError(self.error())

        return res

    def set_nonblocking(self, int v):
        '''Set the nonblocking flag'''
        if self._c_hid == NULL:
            raise ValueError('not open')
        res = hid_set_nonblocking(self._c_hid, v)
        if res < 0:
            raise IOError(self.error())
        return res

    def read(self, int max_length, int timeout_ms=0):
        '''Return a list of integers (0-255) from the device up to max_length bytes.'''
        if self._c_hid == NULL:
            raise ValueError('not open')
        cdef unsigned char lbuff[16]
        cdef unsigned char* cbuff
        cdef size_t c_max_length = max_length
        cdef int c_timeout_ms = timeout_ms
        cdef hid_device * c_hid = self._c_hid
        cdef int n
        if max_length <= 16:
            cbuff = lbuff
        else:
            cbuff = <unsigned char *>malloc(max_length)
        if timeout_ms > 0:
            with nogil:
                n = hid_read_timeout(c_hid, cbuff, c_max_length, c_timeout_ms)
        else:
            with nogil:
                n = hid_read(c_hid, cbuff, c_max_length)
        
        if n >= 0:
            res = []
            for i in range(n):
                res.append(cbuff[i])
        if max_length > 16:
            free(cbuff)
        if n < 0:
            raise IOError(self.error())

        return res

    def get_manufacturer_string(self):
        if self._c_hid == NULL:
            raise ValueError('not open')
        cdef wchar_t buff[255]
        cdef int r = hid_get_manufacturer_string(self._c_hid, buff, 255)
        if r >= 0:
            return U(buff)
        else:
            raise IOError(self.error())

    def get_product_string(self):
        if self._c_hid == NULL:
            raise ValueError('not open')
        cdef wchar_t buff[255]
        cdef int r = hid_get_product_string(self._c_hid, buff, 255)
        if r >= 0:
            return U(buff)
        else:
            raise IOError(self.error())

    def get_serial_number_string(self):
        if self._c_hid == NULL:
            raise ValueError('not open')
        cdef wchar_t buff[255]
        cdef int r = hid_get_serial_number_string(self._c_hid, buff, 255)
        if r >= 0:
            return U(buff)
        else:
            raise IOError(self.error())

    def get_indexed_string(self, int string_index):
        if self._c_hid == NULL:
            raise ValueError('not open')
        cdef wchar_t buff[255]
        cdef int r = hid_get_indexed_string(self._c_hid, string_index, buff, 255)
        if r >= 0:
            return U(buff)
        else:
            raise IOError(self.error())

    def send_feature_report(self, buff):
        if self._c_hid == NULL:
            raise ValueError('not open')
        '''Accept a list of integers (0-255) and send them to the device'''
        # convert to bytes
        if sys.version_info < (3, 0):
            buff = ''.join(map(chr, buff))
        else:
            buff = bytes(buff)
        cdef hid_device * c_hid = self._c_hid
        cdef unsigned char* cbuff = buff # convert to c string
        cdef size_t c_buff_len = len(buff)
        cdef int res
        with nogil:
            res = hid_send_feature_report(c_hid, cbuff, c_buff_len)

        if res >= 0:
            return res
        else:
            raise IOError(self.error())

    def get_feature_report(self, buff, int max_length):
        if self._c_hid == NULL:
            raise ValueError('not open')

        # convert to bytes
        if sys.version_info < (3, 0):
            buff = ''.join(map(chr, buff))
        else:
            buff = bytes(buff)
        cdef unsigned char* cinbuff = buff # convert to c string
        cdef size_t c_inbuff_len = len(buff)

        cdef hid_device * c_hid = self._c_hid
        cdef unsigned char lbuff[16]
        cdef unsigned char* cbuff
        cdef size_t c_max_length = max_length
        cdef int n
        if max_length <= 16:
            cbuff = lbuff
        else:
            cbuff = <unsigned char *>malloc(max_length)

        cdef size_t copylen = c_inbuff_len if c_inbuff_len < c_max_length else c_max_length;

        memcpy(cbuff, cinbuff, copylen);
        memset(cbuff + copylen, 0, max_length-copylen);

        with nogil:
            n = hid_get_feature_report(c_hid, cbuff, c_max_length);
        
        res = []
        if n >= 0:
            for i in range(n):
                res.append(cbuff[i])
        if max_length > 16:
            free(cbuff)
        if n < 0:
            raise IOError(self.error())

        return res

    def error(self):
        if self._c_hid == NULL:
            raise ValueError('not open')
        return U(<wchar_t*>hid_error(self._c_hid))
