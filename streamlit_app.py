GOOGLE_API_KEY = "A_TUA_CHAVE_AQUI"
import streamlit as st
from google import genai

# Configuração do App
st.set_page_config(page_title="ZENITH.IA", page_icon="🤖")
st.title("🤖 ZENITH.IA")

# Lógica para ler a chave secreta de forma segura
if "GOOGLE_API_KEY" in st.secrets:
    client = genai.Client(api_key=st.secrets["GOOGLE_API_KEY"])
        
            if "messages" not in st.session_state:
                    st.session_state.messages = []

                        for message in st.session_state.messages:
                                with st.chat_message(message["role"]):
                                            st.markdown(message["content"])

                                                if prompt := st.chat_input("Como posso ajudar, Salva Aula?"):
                                                        st.session_state.messages.append({"role": "user", "content": prompt})
                                                                with st.chat_message("user"):
                                                                            st.markdown(prompt)

                                                                                    # Chamada ao Gemini
                                                                                            response = client.models.generate_content(
                                                                                                        model="gemini-2.0-flash", 
                                                                                                                    contents=prompt
                                                                                                                            )
                                                                                                                                    
                                                                                                                                            with st.chat_message("assistant"):
                                                                                                                                                        st.markdown(response.text)
                                                                                                                                                                    st.session_state.messages.append({"role": "assistant", "content": response.text})
                                                                                                                                                                    else:
                                                                                                                                                                        st.error("Erro: A variável GOOGLE_API_KEY não foi encontrada nos Secrets!")
                                                                                                                                                        