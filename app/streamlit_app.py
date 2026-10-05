import streamlit as st


st.title("Hello World")

if "click_count" not in st.session_state:
    st.session_state.click_count = 0

if st.button("Click"):
    st.session_state.click_count += 1

st.text(f"Clicks: {st.session_state.click_count}")
