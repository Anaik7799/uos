pub const valid = "auth_date=1000&user=%7B%22id%22%3A42%2C%22first_name%22%3A%22Fixture%22%7D&hash=d8306557ea677424abc44ad5e4f37ca993cfd70cfb359b1ecff578dd46261ce4"

pub const wrong_user = "auth_date=1000&user=%7B%22id%22%3A99%2C%22first_name%22%3A%22Fixture%22%7D&hash=f992c3bab84c16163c3fce52fafb1f2b4fa364f2e06f3a9f229696ca2062cb41"

pub const expired = "auth_date=699&user=%7B%22id%22%3A42%2C%22first_name%22%3A%22Fixture%22%7D&hash=af3c7bfb11407cc65e3d60861977dc070d99f3e5acd05968ef5650b696a18f56"

pub const future = "auth_date=1001&user=%7B%22id%22%3A42%2C%22first_name%22%3A%22Fixture%22%7D&hash=a15f377e032645aeec9cf24db25d7fa23aedbf257e3e36e37923d4cd435dd180"

pub const chat = "auth_date=1000&user=%7B%22id%22%3A42%2C%22first_name%22%3A%22Fixture%22%7D&chat=%7B%22id%22%3A-100123%7D&hash=fad77efa8168fa0952f62d76a865b26dac26bc2dc48dfe0d44c887a2a7e92366"

pub const wrong_chat = "auth_date=1000&user=%7B%22id%22%3A42%2C%22first_name%22%3A%22Fixture%22%7D&chat=%7B%22id%22%3A-100124%7D&hash=4de26f14233282e7736d33409c32eeeb54e31f1e90dc6bcb758398ff2da1dd93"
