package com.dreamgames.controller;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(QueryParamController.class)
class QueryParamControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void echoReturnsSingleParam() throws Exception {
        mockMvc.perform(get("/api/echo").param("hello", "world"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.hello").value("world"));
    }

    @Test
    void echoReturnsMultipleParams() throws Exception {
        mockMvc.perform(get("/api/echo").param("foo", "bar").param("baz", "qux"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.foo").value("bar"))
               .andExpect(jsonPath("$.baz").value("qux"));
    }

    @Test
    void echoReturnsEmptyMapForNoParams() throws Exception {
        mockMvc.perform(get("/api/echo"))
               .andExpect(status().isOk())
               .andExpect(content().json("{}"));
    }
}
